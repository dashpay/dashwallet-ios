//
//  CoinJoinMoveFundsViewModel.swift
//  DashWallet
//
//  Stage machine behind `CoinJoinMoveFundsSheet` — the post-migration
//  "move your mixed coins" flow. The user picks between
//
//   - Dash Wallet balance — the existing one-hop sweep
//     (`WalletSendService.sweepCoinJoin`), and
//   - Shielded balance — a single CoinJoin-drain asset lock
//     (`ShieldedTransferCoordinator.performAssetLock(funding: .coinJoinDrain)`):
//     every mixed-coin UTXO funds the Type 18 lock directly and the shielded
//     pool receives `lock_value - pool_fee` — no transparent intermediate hop.
//     An asset lock may spend at most 100 inputs (Core / Platform), and its
//     shield transition with an InstantSend proof outgrows Platform's size
//     limit from about 65, so an account holding more than 50 is first
//     consolidated onto one fresh address of its own CoinJoin account
//     (`CoinJoinShieldPlanner.consolidationThreshold`), and the drain runs
//     once those outputs are final.
//
//  Failure posture of the shielded flow: a committed asset lock is resumed on
//  its exact outpoint via `resumeAssetLock` (mirroring the internal transfer
//  confirm sheet's "Try again"); a stuck lock that survives the session is
//  picked up by the home tx list's `ShieldedRecoverySheet` on the next
//  launch. A pre-broadcast failure moves nothing — the coins stay in the
//  CoinJoin account and the popup / Settings / Tools surfaces keep offering
//  the move. The consolidation never leaves the CoinJoin account either: if
//  the app dies, or the drain fails, after a consolidation broadcast, the
//  coins sit on one CoinJoin address and the next attempt sees few enough
//  UTXOs to drain them directly.
//

import Combine
import Foundation

@MainActor
final class CoinJoinMoveFundsViewModel: ObservableObject {

    enum Destination: Equatable {
        case wallet
        case shielded
    }

    enum Stage: Equatable {
        /// Destination choice screen.
        case choice
        /// BIP44 sweep in flight.
        case movingToWallet
        /// CoinJoin-drain asset lock in flight; progress detail comes from
        /// `coordinator.phase`.
        case shielding
        case success(Destination)
        /// Shield broadcast accepted but unconfirmed — terminal, non-retryable
        /// (see `ShieldedTransferCoordinator.Phase.submittedUnconfirmed`).
        case submittedUnconfirmed
        /// `destination` picks the retry path: a failed wallet sweep retries
        /// the sweep, a failed shielded flow retries (or resumes) the drain
        /// asset lock.
        case failed(message: String, destination: Destination)
    }

    @Published private(set) var stage: Stage = .choice

    /// Progress of the steps that run before the coordinator's asset lock
    /// when the CoinJoin account cannot be drained as it stands (more than
    /// `CoinJoinShieldPlanner.consolidationThreshold` UTXOs, or some not final
    /// yet). Nil on the direct path, whose checklist is unchanged.
    enum Preparation: Equatable {
        case authorizing
        case preparingCoins
        /// Preparation finished; the coordinator's phase drives the rest.
        case done
    }

    @Published private(set) var preparation: Preparation?

    /// Active row of the prepared path's five-step checklist (Authorizing,
    /// Preparing your coins, Locking funds, Generating proof, Broadcasting);
    /// nil renders every row pending.
    var preparedChecklistIndex: Int? {
        Self.preparedChecklistIndex(preparation: preparation, phase: coordinator.phase)
    }

    nonisolated static func preparedChecklistIndex(
        preparation: Preparation?, phase: ShieldedTransferCoordinator.Phase
    ) -> Int? {
        switch preparation {
        case nil: return nil
        case .authorizing?: return 0
        case .preparingCoins?: return 1
        case .done?:
            switch phase {
            // `.signing` is the coordinator's preauthorized pass-through.
            case .idle, .signing, .locking: return 2
            case .proving: return 3
            case .broadcasting: return 4
            case .success: return 5
            case .failed, .submittedUnconfirmed: return nil
            }
        }
    }

    /// CoinJoin balance snapshot at presentation time — the sweep zeroes the
    /// live balance mid-flow, but the sheet keeps showing what's being moved.
    let amountDuffs: UInt64

    let coordinator = ShieldedTransferCoordinator()

    /// The wallet and network the sheet was opened for (its `amountDuffs`
    /// is that wallet's CoinJoin balance). Every Shielded attempt and retry
    /// is pinned to it: a switch while the sheet is up stops the move.
    private let binding = SwiftDashSDKTransactionSender.CoinJoinWalletBinding.current()

    /// Whether this attempt broadcast (or may have broadcast) a
    /// consolidation, so the coins can sit mid-preparation when it stops.
    private var consolidationSent = false

    /// The committed asset lock a retry must resume, kept here because
    /// `coordinator.reset()` clears the coordinator's copy. A failed resume
    /// does not prove the lock consumed, so only `.success` or
    /// `.submittedUnconfirmed` (the shield was submitted) clears it; until
    /// then every retry resumes it, never a fresh drain.
    private var unresumedLock: (txidWire: Data, vout: UInt32)?

    /// Wire-order txids of this sheet's consolidations whose broadcast outcome
    /// was unknown (they may have reached peers). No new attempt plans until
    /// each one's output is in the CoinJoin account — evidence the wallet
    /// applied it and so shows its inputs as spent. The output stays until a
    /// drain spends it, unlike the transaction record, which the SDK drops
    /// once it is chainlocked.
    private var unobservedConsolidationTxids: [Data] = []

    private var cancellables = Set<AnyCancellable>()

    init(amountDuffs: UInt64) {
        self.amountDuffs = amountDuffs
        // The step checklist reads `coordinator.phase` — republish its
        // changes so SwiftUI re-renders while `stage` itself is stable.
        coordinator.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var isInFlight: Bool {
        switch stage {
        case .movingToWallet, .shielding:
            return true
        default:
            return false
        }
    }

    // MARK: Actions

    /// Destination 1: the existing one-hop sweep into the spendable BIP44
    /// balance. Auth-cancel returns to the choice screen silently.
    func moveToWallet() async {
        guard !isInFlight else { return }
        stage = .movingToWallet
        do {
            guard let binding else {
                throw SwiftDashSDKTransactionSender.SendError.walletNotReady("no wallet when the sheet opened")
            }
            _ = try await WalletSendService.shared.sweepCoinJoin(expecting: binding)
            stage = .success(.wallet)
        } catch {
            if let message = WalletSendService.coinJoinSweepUserMessage(for: error) {
                stage = .failed(message: message, destination: .wallet)
            } else {
                stage = .choice
            }
        }
    }

    /// Destination 2: one CoinJoin-drain asset lock — every mixed-coin UTXO
    /// funds the Type 18 lock directly (no transparent hop) and the shielded
    /// pool receives the drained value minus the pool fee.
    ///
    /// When the account holds more UTXOs than one drain may safely spend
    /// (`CoinJoinShieldPlanner.consolidationThreshold`), they
    /// are first consolidated onto one fresh CoinJoin address (see
    /// `prepareCoinJoinInputs`). Either way the user is asked once, up front;
    /// the plan is made from the UTXO set read after the prompt, so coins that
    /// arrive while it is open are planned for, and the drain runs
    /// `preauthorized`. The move is pinned to `binding`: a wallet or network
    /// switch since the sheet opened stops it.
    func moveToShielded() async {
        guard !isInFlight else { return }
        // A committed lock is resumed, never followed by a second drain.
        if unresumedLock != nil {
            preparation = nil
            await retryShielded()
            return
        }
        stage = .shielding
        preparation = nil
        consolidationSent = false
        if !unobservedConsolidationTxids.isEmpty {
            guard let state = binding.flatMap({ SwiftDashSDKTransactionSender.coinJoinUtxoState(expecting: $0) }) else {
                Self.log("move to Shielded — the active wallet changed, or its CoinJoin UTXOs can't be read; stopping")
                stage = .failed(message: Self.genericFailureMessage, destination: .shielded)
                return
            }
            // Any output counts, final or not: it shows the wallet applied it.
            guard Set(state.entries.map(\.txid)).isSuperset(of: unobservedConsolidationTxids) else {
                Self.log("move to Shielded — an earlier consolidation is not in the wallet yet, not replanning")
                stage = .failed(message: Self.preparingMessage, destination: .shielded)
                return
            }
            unobservedConsolidationTxids = []
        }
        // A prior failed attempt leaves the coordinator terminal; reset so
        // `beginTransfer()` doesn't silently bail.
        if coordinator.phase != .idle {
            coordinator.reset()
        }

        // Read before the prompt only to choose the checklist, and to stop
        // without asking for the PIN when the move can't run anyway.
        let initial = Self.plan(expecting: binding)
        Self.log("move to Shielded — before authorization: \(initial.description)")
        guard initial.state != nil else {
            Self.log("move to Shielded — CoinJoin UTXOs could not be read, or the active wallet changed; stopping")
            stage = .failed(message: Self.genericFailureMessage, destination: .shielded)
            return
        }
        if initial.needsPreparation {
            preparation = .authorizing
        }

        do {
            try await DWIdentityAuthorizer().authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            Self.log("move to Shielded — authorization cancelled")
            preparation = nil
            stage = .choice
            return
        } catch {
            Self.log("move to Shielded — authorization failed")
            preparation = nil
            stage = .failed(
                message: ShieldedTransferCoordinator.CoordinatorError.authFailed.errorDescription
                    ?? Self.genericFailureMessage,
                destination: .shielded)
            return
        }

        let current = Self.plan(expecting: binding)
        Self.log("move to Shielded — after authorization: \(current.description)")
        // An unreadable account must not fall through to the drain: the SDK
        // drain enumerates the account itself and could spend more inputs
        // than one asset lock may carry.
        guard let state = current.state else {
            Self.log("move to Shielded — CoinJoin UTXOs could not be read, or the active wallet changed; stopping")
            preparation = nil
            stage = .failed(message: Self.genericFailureMessage, destination: .shielded)
            return
        }
        if current.needsPreparation {
            preparation = .preparingCoins
            if let message = await prepareCoinJoinInputs(state) {
                preparation = nil
                SwiftDashSDKWalletState.shared.refreshCoinJoinBalance()
                stage = .failed(message: message, destination: .shielded)
                return
            }
        }
        if preparation != nil {
            preparation = .done
        }

        guard !Task.isCancelled else {
            Self.log("move to Shielded — cancelled before the drain")
            let message = consolidationSent ? Self.preparingMessage : Self.genericFailureMessage
            preparation = nil
            stage = .failed(message: message, destination: .shielded)
            return
        }
        // An empty account is reported by the coordinator / SDK preflight
        // exactly as before.
        await DWIdentityAuthorizer.preauthorized { [self] in
            await coordinator.performAssetLock(funding: .coinJoinDrain, expecting: state.binding)
        }
        // The coordinator's own cancel check (before any lock is built) after
        // a consolidation: the coins may sit mid-preparation, so say so
        // instead of returning to the choice. Any other failure is reported
        // as usual.
        if Task.isCancelled, consolidationSent,
           case .failed(let message) = coordinator.phase,
           message == ShieldedTransferCoordinator.CoordinatorError.authCancelled.errorDescription {
            Self.log("move to Shielded — cancelled before the drain")
            coordinator.reset()
            preparation = nil
            SwiftDashSDKWalletState.shared.refreshCoinJoinBalance()
            stage = .failed(message: Self.preparingMessage, destination: .shielded)
            return
        }
        finishFromCoordinatorPhase()
    }

    /// The CoinJoin account's UTXO snapshot and the planner's verdict on it.
    private struct Plan {
        let state: SwiftDashSDKTransactionSender.CoinJoinUtxoState?
        let step: CoinJoinShieldPlanner.Step?

        var needsPreparation: Bool {
            switch step {
            case .consolidate?, .awaitFinality?: return true
            case .drain?, .nothingToMove?, nil: return false
            }
        }

        var description: String {
            "CoinJoin UTXOs n=\(state?.count ?? -1) final=\(state?.finalCount ?? -1) total=\(state?.totalDuffs ?? 0) duffs, plan=\(step.map { String(describing: $0) } ?? "unknown")"
        }
    }

    /// - Parameter binding: nil state unless it is the active wallet and
    ///   network (also when it is nil: no wallet was bound).
    private static func plan(expecting binding: SwiftDashSDKTransactionSender.CoinJoinWalletBinding?) -> Plan {
        guard let binding else { return Plan(state: nil, step: nil) }
        let state = SwiftDashSDKTransactionSender.coinJoinUtxoState(expecting: binding)
        return Plan(
            state: state,
            step: state.map { CoinJoinShieldPlanner.nextStep(utxoCount: $0.count, finalCount: $0.finalCount) })
    }

    // MARK: Preparation (more than 50 mixed coins, or coins not yet final)

    /// How long to wait for a consolidation's outputs (or any not-yet-final
    /// CoinJoin UTXO) to become final. InstantSend normally locks within
    /// seconds; past this the attempt stops with a retryable message rather
    /// than hold the sheet open.
    static let finalityTimeout: TimeInterval = 180

    /// Consolidate (when over the threshold) and wait for finality. Returns nil when
    /// the account is ready to drain, or the message to show otherwise. Every
    /// step is pinned to `state.binding`, and a cancelled task never returns
    /// nil, so it never reaches the drain.
    ///
    /// One consolidation per attempt: a partial one stops the attempt with a
    /// retryable message, and the next attempt consolidates what is left
    /// together with the outputs already made.
    ///
    /// - Parameter state: the UTXO set read after authorization.
    private func prepareCoinJoinInputs(_ state: SwiftDashSDKTransactionSender.CoinJoinUtxoState) async -> String? {
        // Same execution-boundary check the coordinator makes for the drain:
        // the sweep is whole-account too, and a scan that restarted while the
        // prompt was open could still be discovering UTXOs.
        guard SyncingActivityMonitor.shared.state == .syncDone else {
            Self.log("move to Shielded — preparation refused, chain not synced")
            return ShieldedTransferCoordinator.CoordinatorError.coinJoinDrainRequiresSync.errorDescription
        }
        var consolidationTxids: [Data] = []
        if CoinJoinShieldPlanner.nextStep(utxoCount: state.count, finalCount: state.finalCount) == .consolidate {
            do {
                try WalletSendService.ensureOnline()
            } catch {
                return error.localizedDescription
            }
            guard let address = SwiftDashSDKTransactionSender.unusedCoinJoinAddress(for: state.binding) else {
                Self.log("move to Shielded — no unused CoinJoin address for the consolidation")
                return Self.genericFailureMessage
            }
            let chunks = SwiftDashSDKTransactionSender.balancedChunks(
                Array(repeating: 0, count: state.count),
                maxPerChunk: SwiftDashSDKTransactionSender.maxInputsPerSweep
            ).map(\.count)
            Self.log("move to Shielded — consolidating n=\(state.count) CoinJoin UTXOs into \(chunks.count) tx(s) \(chunks)")
            guard !Task.isCancelled else {
                Self.log("move to Shielded — cancelled before the consolidation")
                return Self.genericFailureMessage
            }
            do {
                // Off the main actor so the checklist renders first; the
                // sender hops back to main for the SDK calls themselves.
                let binding = state.binding
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try SwiftDashSDKTransactionSender.sweepCoinJoin(to: address, expecting: binding)
                }.value
                consolidationTxids = outcome.txids
                unobservedConsolidationTxids = outcome.unknownTxids
                consolidationSent = !outcome.txids.isEmpty
                // Counts only: a txid leads to the consolidation address.
                Self.log("move to Shielded — consolidation broadcast \(outcome.txids.count) tx(s), \(outcome.failedChunkCount) failed\(outcome.firstFailure.map { " first failure: \(Self.summary(of: $0))" } ?? "")")
                // A chunk that failed may still have reached peers (an
                // unconfirmed broadcast), and the wallet may not show its
                // inputs as spent yet; a drain now could spend them a second
                // time. Stop here; the next attempt plans from the UTXO set
                // as the wallet reads it then.
                if outcome.isPartial {
                    Self.log("move to Shielded — partial consolidation, stopping before the drain")
                    return NSLocalizedString(
                        "Some of your mixed coins were prepared. Please try again to move them to your Shielded balance.",
                        comment: "CoinJoin")
                }
            } catch let error as SwiftDashSDKTransactionSender.CoinJoinSweepUnknownError {
                // The broadcasts may have reached peers. The wallet applies a
                // transaction before waiting for them, which spends its inputs
                // locally; the next attempt waits until their outputs show.
                consolidationSent = true
                unobservedConsolidationTxids = error.unknownTxids
                Self.log("move to Shielded — consolidation outcome unknown")
                return Self.preparingMessage
            } catch {
                Self.log("move to Shielded — consolidation failed, nothing accepted: \(Self.summary(of: error))")
                return Self.genericFailureMessage
            }
            guard !consolidationTxids.isEmpty else {
                Self.log("move to Shielded — consolidation produced no transaction")
                return Self.genericFailureMessage
            }
        }

        // Wait until the consolidation outputs are back in the account and
        // final, and — on the direct-but-not-final path — until every CoinJoin
        // UTXO is final: the drain builder spends final inputs only.
        let txids = consolidationTxids
        let waitStart = Date()
        let waitedResult: (state: SwiftDashSDKTransactionSender.CoinJoinUtxoState, satisfied: Bool)?
        do {
            waitedResult = try await SwiftDashSDKTransactionSender.waitForCoinJoinUtxoState(
                binding: state.binding,
                timeout: Self.finalityTimeout
            ) { state in
                if !txids.isEmpty {
                    return CoinJoinShieldPlanner.consolidationSettled(
                        consolidationTxids: txids, utxos: state.txidFinality)
                }
                return state.finalCount == state.count
            }
        } catch {
            Self.log("move to Shielded — cancelled while waiting for finality")
            return txids.isEmpty ? Self.genericFailureMessage : Self.preparingMessage
        }
        guard let waited = waitedResult else {
            Self.log("move to Shielded — the active wallet changed, or CoinJoin UTXOs could not be read")
            return txids.isEmpty ? Self.genericFailureMessage : Self.preparingMessage
        }
        let after = waited.state
        let waitedSeconds = Int(Date().timeIntervalSince(waitStart).rounded())
        Self.log(
            "move to Shielded — finality wait \(waited.satisfied ? "settled" : "timed out") after \(waitedSeconds)s "
                + "(cap \(Int(Self.finalityTimeout))s): n=\(after.count) final=\(after.finalCount)")

        if !waited.satisfied {
            if !txids.isEmpty || after.finalCount == 0 {
                // The consolidated coins are safe on their CoinJoin address;
                // a later attempt drains them once they are final.
                return Self.preparingMessage
            }
            // Direct path, some coins still unconfirmed: drain what is final,
            // exactly as before this preparation existed. The rest stays in
            // the CoinJoin account for a later move.
        }

        switch CoinJoinShieldPlanner.nextStep(utxoCount: after.count, finalCount: after.finalCount) {
        case .consolidate:
            Self.log("move to Shielded — still n=\(after.count) UTXOs after consolidation")
            return Self.genericFailureMessage
        case .nothingToMove:
            return Self.genericFailureMessage
        case .drain, .awaitFinality:
            guard !Task.isCancelled else {
                Self.log("move to Shielded — cancelled before the drain")
                return txids.isEmpty ? Self.genericFailureMessage : Self.preparingMessage
            }
            return nil
        }
    }

    private static var preparingMessage: String {
        NSLocalizedString(
            "Your mixed coins are being prepared for the Shielded balance. Please try again in a few minutes.",
            comment: "CoinJoin")
    }

    private static var genericFailureMessage: String {
        NSLocalizedString("Couldn't move your CoinJoin funds. Please try again.", comment: "CoinJoin")
    }

    /// Exported-log line (DWLogger reaches "Share logs"; os.Logger does not).
    private static func log(_ message: String) {
        DWLogger.log("🛡️ COINJOIN-SHIELD :: \(message)", className: "CoinJoinMoveFundsViewModel")
    }

    /// An error's type and code for the exported log. Not its description:
    /// send and builder errors quote txids, outpoints and addresses, which
    /// lead to the consolidation address (the sender's os.Logger keeps the
    /// detail, outside the export).
    private static func summary(of error: Error) -> String {
        let nsError = error as NSError
        return "\(type(of: error)) \(nsError.domain) #\(nsError.code)"
    }

    /// "Try again" from a failed shielded attempt. Mirrors
    /// `InternalTransferConfirmSheet.tryAgain`: a committed asset lock is
    /// RESUMED on its exact outpoint (building a second lock would strand the
    /// first); otherwise a fresh drain build runs — a pre-broadcast failure
    /// left the CoinJoin account untouched.
    func retryShielded() async {
        guard !isInFlight else { return }
        if let op = coordinator.lastAssetLockOutPoint ?? unresumedLock {
            unresumedLock = op
            guard let binding, binding == SwiftDashSDKTransactionSender.CoinJoinWalletBinding.current() else {
                Self.log("move to Shielded — resume refused, the active wallet changed")
                stage = .failed(message: Self.genericFailureMessage, destination: .shielded)
                return
            }
            stage = .shielding
            coordinator.reset()
            // Resume re-authorizes on its own (fresh user action).
            await coordinator.resumeAssetLock(
                outPointTxidWire: op.txidWire, outPointVout: op.vout, expecting: binding)
            switch coordinator.phase {
            case .success, .submittedUnconfirmed:
                unresumedLock = nil
            default:
                break
            }
            finishFromCoordinatorPhase()
            return
        }
        // No committed lock to resume: plan afresh. A consolidation that
        // already landed shows up as a few UTXOs on one CoinJoin address, so
        // this drains them directly (waiting for finality first if needed).
        coordinator.reset()
        await moveToShielded()
    }

    private func finishFromCoordinatorPhase() {
        // The drain consumed (or may have consumed) the CoinJoin balance —
        // re-tally so the popup/Settings surfaces self-clear without waiting
        // for the next SPV balance event. Also correct for failures: the
        // re-tally just reads the SDK's current UTXO set.
        SwiftDashSDKWalletState.shared.refreshCoinJoinBalance()
        switch coordinator.phase {
        case .success:
            stage = .success(.shielded)
        case .submittedUnconfirmed:
            stage = .submittedUnconfirmed
        case .failed(let message):
            // A cancelled PIN prompt is a user decision, not an error —
            // return to the destination choice (mirrors the wallet leg's
            // auth-cancel handling). Message-compare against the same
            // localized source the coordinator maps the cancel to.
            if message == ShieldedTransferCoordinator.CoordinatorError.authCancelled.errorDescription {
                coordinator.reset()
                stage = .choice
            } else {
                stage = .failed(message: message, destination: .shielded)
            }
        default:
            // The coordinator's single-flight gate refused the call (phase
            // wasn't idle). Surface a retryable failure rather than hang.
            stage = .failed(message: Self.genericFailureMessage, destination: .shielded)
        }
    }
}

#if DEBUG
extension CoinJoinMoveFundsViewModel {

    /// Preview-only constructor: builds the model and forces it to `stage`.
    ///
    /// `stage` is `private(set)`, so this has to live in the same file as the
    /// property rather than beside the previews that use it.
    static func preview(amountDuffs: UInt64, stage: Stage) -> CoinJoinMoveFundsViewModel {
        let model = CoinJoinMoveFundsViewModel(amountDuffs: amountDuffs)
        model.stage = stage
        return model
    }
}
#endif
