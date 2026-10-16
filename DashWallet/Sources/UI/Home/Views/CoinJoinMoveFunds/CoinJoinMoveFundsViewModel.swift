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
//     An asset lock may spend at most 100 inputs, so an account holding more
//     is first consolidated onto one fresh address of its own CoinJoin
//     account (`CoinJoinShieldPlanner`), and the drain runs once those
//     outputs are final.
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
    /// `CoinJoinShieldPlanner.maxAssetLockInputs` UTXOs, or some not final
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
            _ = try await WalletSendService.shared.sweepCoinJoin()
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
    /// When the account holds more UTXOs than one asset lock may spend, they
    /// are first consolidated onto one fresh CoinJoin address (see
    /// `prepareCoinJoinInputs`). Either way the user is asked once: on the
    /// direct path the coordinator runs its own PIN/biometric gate; on the
    /// prepared path this model runs the same gate up front and the drain
    /// runs `preauthorized`.
    func moveToShielded() async {
        guard !isInFlight else { return }
        stage = .shielding
        preparation = nil
        // A prior failed attempt leaves the coordinator terminal; reset so
        // `beginTransfer()` doesn't silently bail.
        if coordinator.phase != .idle {
            coordinator.reset()
        }

        let initial = SwiftDashSDKTransactionSender.coinJoinUtxoState()
        let step = initial.map {
            CoinJoinShieldPlanner.nextStep(utxoCount: $0.count, finalCount: $0.finalCount)
        }
        Self.log("move to Shielded — CoinJoin UTXOs n=\(initial?.count ?? -1) final=\(initial?.finalCount ?? -1) total=\(initial?.totalDuffs ?? 0) duffs, plan=\(step.map { String(describing: $0) } ?? "unknown")")

        switch step {
        case .consolidate?, .awaitFinality?:
            await prepareThenDrain()
        case .drain?, .nothingToMove?, nil:
            // Unchanged direct path. An empty account or an unbound host is
            // reported by the coordinator / SDK preflight exactly as before.
            await coordinator.performAssetLock(funding: .coinJoinDrain)
            finishFromCoordinatorPhase()
        }
    }

    // MARK: Preparation (more than 100 mixed coins, or coins not yet final)

    /// How long to wait for a consolidation's outputs (or any not-yet-final
    /// CoinJoin UTXO) to become final. InstantSend normally locks within
    /// seconds; past this the attempt stops with a retryable message rather
    /// than hold the sheet open.
    static let finalityTimeout: TimeInterval = 180

    /// Authorize once, bring the CoinJoin account into a drainable shape, then
    /// run the coordinator's drain without a second prompt.
    private func prepareThenDrain() async {
        preparation = .authorizing
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

        preparation = .preparingCoins
        if let message = await prepareCoinJoinInputs() {
            preparation = nil
            SwiftDashSDKWalletState.shared.refreshCoinJoinBalance()
            stage = .failed(message: message, destination: .shielded)
            return
        }

        preparation = .done
        await DWIdentityAuthorizer.preauthorized { [self] in
            await coordinator.performAssetLock(funding: .coinJoinDrain)
        }
        finishFromCoordinatorPhase()
    }

    /// Consolidate (when over the cap) and wait for finality. Returns nil when
    /// the account is ready to drain, or the message to show otherwise.
    ///
    /// One consolidation per attempt: if it is partial and the account is
    /// still over the cap afterwards, the attempt stops with a retryable
    /// message, and the next attempt consolidates what is left together with
    /// the outputs already made.
    private func prepareCoinJoinInputs() async -> String? {
        // Same execution-boundary check the coordinator makes for the drain:
        // the sweep is whole-account too, and a scan that restarted while the
        // prompt was open could still be discovering UTXOs.
        guard SyncingActivityMonitor.shared.state == .syncDone else {
            Self.log("move to Shielded — preparation refused, chain not synced")
            return ShieldedTransferCoordinator.CoordinatorError.coinJoinDrainRequiresSync.errorDescription
        }
        guard let state = SwiftDashSDKTransactionSender.coinJoinUtxoState() else {
            return Self.genericFailureMessage
        }

        var consolidationTxids: [Data] = []
        var consolidationPartial = false
        if CoinJoinShieldPlanner.nextStep(utxoCount: state.count, finalCount: state.finalCount) == .consolidate {
            do {
                try WalletSendService.ensureOnline()
            } catch {
                return error.localizedDescription
            }
            guard let address = SwiftDashSDKTransactionSender.unusedCoinJoinAddress() else {
                Self.log("move to Shielded — no unused CoinJoin address for the consolidation")
                return Self.genericFailureMessage
            }
            let chunks = SwiftDashSDKTransactionSender.balancedChunks(
                Array(repeating: 0, count: state.count),
                maxPerChunk: SwiftDashSDKTransactionSender.maxInputsPerSweep
            ).map(\.count)
            Self.log("move to Shielded — consolidating n=\(state.count) CoinJoin UTXOs into \(chunks.count) tx(s) \(chunks) to \(address)")
            do {
                // Off the main actor so the checklist renders first; the
                // sender hops back to main for the SDK calls themselves.
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try SwiftDashSDKTransactionSender.sweepCoinJoin(to: address)
                }.value
                consolidationTxids = outcome.txids
                consolidationPartial = outcome.isPartial
                Self.log("move to Shielded — consolidation broadcast \(outcome.txids.count) tx(s), \(outcome.failedChunkCount) failed: \(outcome.txids.map(Self.displayHex).joined(separator: ","))\(outcome.firstFailure.map { " first failure: \(String(describing: $0))" } ?? "")")
            } catch {
                Self.log("move to Shielded — consolidation failed, nothing broadcast: \(String(describing: error))")
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
        let waited = await SwiftDashSDKTransactionSender.waitForCoinJoinUtxoState(
            timeout: Self.finalityTimeout
        ) { state in
            if !txids.isEmpty {
                return CoinJoinShieldPlanner.consolidationSettled(
                    consolidationTxids: txids, utxos: state.txidFinality)
            }
            return state.finalCount == state.count
        }
        guard let waited else { return Self.genericFailureMessage }
        let after = waited.state
        Self.log("move to Shielded — finality wait \(waited.satisfied ? "settled" : "timed out") after \(Int(Self.finalityTimeout))s cap: n=\(after.count) final=\(after.finalCount)")

        if !waited.satisfied {
            if !txids.isEmpty || after.finalCount == 0 {
                // The consolidated coins are safe on their CoinJoin address;
                // a later attempt drains them once they are final.
                return NSLocalizedString(
                    "Your mixed coins are being prepared for the Shielded balance. Please try again in a few minutes.",
                    comment: "CoinJoin")
            }
            // Direct path, some coins still unconfirmed: drain what is final,
            // exactly as before this preparation existed. The rest stays in
            // the CoinJoin account for a later move.
        }

        switch CoinJoinShieldPlanner.nextStep(utxoCount: after.count, finalCount: after.finalCount) {
        case .consolidate:
            Self.log("move to Shielded — still n=\(after.count) UTXOs after consolidation (partial=\(consolidationPartial))")
            return consolidationPartial
                ? NSLocalizedString(
                    "Some of your mixed coins were prepared. Please try again to move them to your Shielded balance.",
                    comment: "CoinJoin")
                : Self.genericFailureMessage
        case .nothingToMove:
            return Self.genericFailureMessage
        case .drain, .awaitFinality:
            return nil
        }
    }

    private static var genericFailureMessage: String {
        NSLocalizedString("Couldn't move your CoinJoin funds. Please try again.", comment: "CoinJoin")
    }

    /// Exported-log line (DWLogger reaches "Share logs"; os.Logger does not).
    private static func log(_ message: String) {
        DWLogger.log("🛡️ COINJOIN-SHIELD :: \(message)", className: "CoinJoinMoveFundsViewModel")
    }

    /// Display-order (explorer) hex of a wire-order txid.
    private static func displayHex(_ txidWire: Data) -> String {
        txidWire.reversed().map { String(format: "%02x", $0) }.joined()
    }

    /// "Try again" from a failed shielded attempt. Mirrors
    /// `InternalTransferConfirmSheet.tryAgain`: a committed asset lock is
    /// RESUMED on its exact outpoint (building a second lock would strand the
    /// first); otherwise a fresh drain build runs — a pre-broadcast failure
    /// left the CoinJoin account untouched.
    func retryShielded() async {
        guard !isInFlight else { return }
        if let op = coordinator.lastAssetLockOutPoint {
            stage = .shielding
            coordinator.reset()
            // Resume re-authorizes on its own (fresh user action).
            await coordinator.resumeAssetLock(outPointTxidWire: op.txidWire, outPointVout: op.vout)
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
