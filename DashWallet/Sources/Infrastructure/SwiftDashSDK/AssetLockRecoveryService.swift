//
//  AssetLockRecoveryService.swift
//  DashWallet
//
//  User-initiated retry of a funding asset lock parked in a
//  non-terminal state — built/broadcast but never IS/CL-locked,
//  locked on Core but whose Platform transition never landed (app
//  killed, network drop), or rebuilt from chain by a restore, which
//  loses the local record of whether that transition ever landed.
//  Dispatches by funding type to the SDK's
//  crash-recovery resume entry points, which pick up the EXISTING
//  tracked outpoint and drive whatever stages remain (rebroadcast,
//  IS/CL wait, Platform submit, consume) — no second lock is ever
//  built, so a retry can't strand more funds.
//
//  Routes handled here (the tx-detail "Rebroadcast" button):
//    1/2 — identity top-up (bound / not-bound):
//          `resumeTopUpWithAssetLock` against the wallet's identity.
//    4   — Core → Platform address funding:
//          `ShieldedTransferCoordinator.resumeFundPlatform`.
//    5   — Core → Shielded funding:
//          `ShieldedTransferCoordinator.resumeAssetLock`.
//  Deliberately NOT handled: 0 (identity registration) and
//  3 (invitation) — those locks recover through the Join DashPay
//  registration flow, which owns key preparation and phase UI.
//

import Foundation
import OSLog
import SwiftDashSDK
import SwiftData

@MainActor
struct AssetLockRecoveryService {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.asset-lock-recovery")

    enum RecoveryError: LocalizedError {
        case notReady
        case noIdentity
        case unsupportedRoute
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notReady:
                return NSLocalizedString("Wallet is not ready", comment: "DashPay")
            case .noIdentity:
                return NSLocalizedString("This wallet has no identity to top up.", comment: "Asset-lock retry: identity top-up with no identity")
            case .unsupportedRoute:
                return NSLocalizedString("This transfer can't be retried from here.", comment: "Asset-lock retry: unsupported funding route")
            case .failed(let message):
                return message
            }
        }
    }

    /// Funding routes the tx-detail retry button supports. Pure
    /// predicate, callable off the main actor (`TxDetailModel` derives
    /// rows outside it).
    nonisolated static func supportsRetry(fundingTypeRaw: Int) -> Bool {
        [1, 2, 4, 5].contains(fundingTypeRaw)
    }

    /// `AssetLockStatus::RecoveredFromChain` as it crosses the FFI — a lock
    /// reconstructed from a chain-locked record (a restore, or an
    /// unauthenticated already-consumed report), whose Platform-side
    /// consumption is unknown.
    nonisolated static let recoveredFromChainStatus = 5

    /// Asset-lock statuses whose transfer has not been shown to be finished,
    /// and which therefore still deserve a retry action. Pure predicate so the
    /// rule is testable without a `TxDetailModel` and its lookups; the view
    /// model calls this rather than owning it, so the service and its tests are
    /// the single source of truth for what a retry is offered on.
    nonisolated static func statusAllowsRetry(_ statusRaw: Int) -> Bool {
        (0...3).contains(statusRaw) || statusRaw == recoveredFromChainStatus
    }

    /// The bulk pass is deliberately narrower than the per-row action.
    ///
    /// Route: type 5 (Core → Shielded) only. It is the route this feature
    /// exists for, and the only one whose resume classifies an already-consumed
    /// lock as a non-failure. A restore rebuilds identity top-ups (1/2) and
    /// Core → Platform address fundings (4) as `RecoveredFromChain` too, but
    /// `resumeTopUpWithAssetLock` surfaces an already-consumed lock as an
    /// opaque consensus rejection and `resumeFundPlatform` flattens every error
    /// into `.failed`. Those locks would therefore fail on every run, never earn
    /// a probe, never leave `pendingRecoveries()` — and, since the snapshot is
    /// dictionary-ordered, could burn the consecutive-failure budget before the
    /// pass reaches a single recoverable shielded lock. They keep their per-row
    /// "Rebroadcast" action, where one failure costs one tap.
    nonisolated static let bulkFundingTypeRaw = 5

    /// Statuses the bulk pass acts on: chain-final on Core, Platform side still
    /// open. 0 and 1 are excluded even though the per-row action offers them —
    /// an unlocked lock re-broadcasts and then blocks on the IS/CL wait, so one
    /// transaction evicted from every mempool can hold "Finishing 3 of 23"
    /// indefinitely with nothing to skip it. Re-broadcasting is a per-row
    /// decision; a batch is not the place to wait on the network.
    nonisolated static func bulkStatusAllowsRecovery(_ statusRaw: Int) -> Bool {
        [2, 3, recoveredFromChainStatus].contains(statusRaw)
    }

    /// What a resume that did not throw actually established.
    enum Outcome: Equatable {
        /// The transfer finished on Platform during this call.
        case completed
        /// Platform reported the outpoint already spent. That report is not
        /// quorum-authenticated, so it proves the retry has nothing left to
        /// do without proving this particular transfer succeeded — say that
        /// rather than claiming a completion we did not witness.
        case completionUnconfirmed
        /// The transition was accepted but its result could not be read back
        /// (`shieldedSpendUnconfirmed`). Distinct from both of the above: the
        /// transfer may well be settling right now, so this is neither a
        /// completion nor an answer about the outpoint. Re-submitting risks a
        /// double-spend, so the retry is suppressed for this pass and the next
        /// shielded sync is what resolves it.
        case submittedAwaitingSync
    }

    /// Retry the transfer for the tracked lock at (`txidWire`, `vout`).
    /// PIN-gated (directly or inside the transfer coordinator). Throws
    /// `DWIdentityAuthorizer.AuthError.cancelled` when the user backs
    /// out of the PIN prompt — callers treat that as a non-error.
    /// Returns only after the resume ran to completion, which for a
    /// still-unlocked transaction includes the IS/CL wait.
    @discardableResult
    func retry(fundingTypeRaw: Int,
               txidWire: Data,
               vout: UInt32,
               refreshLookup: Bool = true) async throws -> Outcome {
        // Resolved before the resume suspends: a wallet switch during the
        // round-trip must not file this probe under whatever wallet is active
        // when the answer arrives.
        let originatingWalletIdHex = AssetLockProbeStore.currentWalletIdHex()
        Self.logger.info("🔁 LOCK-RETRY :: type=\(fundingTypeRaw, privacy: .public) vout=\(vout, privacy: .public)")
        let outcome: Outcome
        switch fundingTypeRaw {
        case 1, 2:
            try await retryIdentityTopUp(txidWire: txidWire, vout: vout)
            outcome = .completed
        case 4, 5:
            // Both coordinator routes report their outcome through the
            // terminal phase rather than throwing, so the resume call and
            // the phase check stay one pair — a future route added here
            // can't forget the check.
            let coordinator = ShieldedTransferCoordinator()
            if fundingTypeRaw == 4 {
                let recipientAmountDuffs = try Self.coreToPlatformRecipientAmountDuffs(
                    txidWire: txidWire,
                    vout: vout)
                await coordinator.resumeFundPlatform(
                    outPointTxidWire: txidWire,
                    outPointVout: vout,
                    recipientAmountDuffs: recipientAmountDuffs)
            } else {
                await coordinator.resumeAssetLock(outPointTxidWire: txidWire, outPointVout: vout)
            }
            try Self.checkTerminalPhase(coordinator)
            // Branch on the coordinator's typed report, NOT on
            // `.submittedUnconfirmed`: that phase has two producers and only one
            // of them says anything about this outpoint. `shieldedSpendUnconfirmed`
            // means the transition was accepted but its result could not be read
            // back — persisting an already-spent probe for it would report
            // "Already spent" for a transfer that may still be settling, and
            // would suppress the retry that settles it.
            if coordinator.phase == .submittedUnconfirmed,
               coordinator.lastResumeReport != .alreadyConsumed {
                // The other producer of that phase: accepted, result unread.
                // No probe — nothing here is evidence about the outpoint, and
                // recording one would report "Already spent" for a transfer
                // that may still be settling and suppress the retry that
                // settles it. Reporting `.completed` would be worse still.
                outcome = .submittedAwaitingSync
            } else if coordinator.lastResumeReport == .alreadyConsumed {
                // Platform reported this outpoint already spent. The SDK keeps
                // the lock at `RecoveredFromChain` (the report is not
                // quorum-authenticated), so record the probe here — otherwise
                // the answer dies with this call and every later launch offers
                // the same futile retry. Recorded at the service layer so the
                // single-row and bulk callers share it.
                AssetLockProbeStore.shared.record(txid: txidWire, walletIdHex: originatingWalletIdHex)
                outcome = .completionUnconfirmed
            } else {
                outcome = .completed
            }
        default:
            throw RecoveryError.unsupportedRoute
        }
        if refreshLookup {
            await ShieldedTxLookup.shared.refresh(reason: "asset-lock-recovery-completed")
        }
        Self.logger.info(
            "🔁 LOCK-RETRY :: completed type=\(fundingTypeRaw, privacy: .public) outcome=\(String(describing: outcome), privacy: .public)")
        return outcome
    }

    // MARK: - Bulk recovery

    /// One funding lock the bulk pass will act on.
    struct PendingRecovery {
        let txidWire: Data
        let vout: UInt32
        let fundingTypeRaw: Int
    }

    /// What a bulk pass ended up doing.
    struct BulkOutcome {
        var completed = 0
        var alreadySpent = 0
        /// Submitted, result not yet readable. Neither a win nor a failure —
        /// counted apart so the summary never folds it into "finished".
        var awaitingSync = 0
        var failed = 0
        var cancelled = false
        /// First failure's message, surfaced so a run that mostly failed says
        /// WHY on screen instead of a bare count. Bulk failures land in OSLog,
        /// which a diagnostic export never captures (the gap ticket 32004
        /// found for sends), so the count alone left nothing to diagnose from.
        var firstFailureMessage: String?
        /// Set when the pass gave up early after repeated failures.
        var stoppedAfterRepeatedFailures = false
        /// Set when the batch never started because authentication failed —
        /// distinct from `cancelled`, which means the user backed out.
        var authFailureMessage: String?

        var attempted: Int { completed + alreadySpent + awaitingSync + failed }
    }

    /// Consecutive failures after which the pass stops. A network refusing one
    /// lock will refuse the next; grinding through dozens of proof builds
    /// against it wastes minutes and tells the user nothing new.
    static let consecutiveFailureLimit = 3

    /// What one lock in the pass turned out to be. Separated from the loop so
    /// the tally and the stop rule are a pure function of the sequence of
    /// results — testable without a wallet, a network or a PIN prompt, which is
    /// the only reason this bookkeeping was previously unpinned.
    enum BulkStep: Equatable {
        case completed
        case alreadySpent
        case awaitingSync
        case cancelled
        case failed(String)
    }

    /// Fold one step into the running tally. Returns `true` when the pass must
    /// stop — the user cancelled, or the failure run hit
    /// `consecutiveFailureLimit`.
    @discardableResult
    static func apply(_ step: BulkStep,
                      to outcome: inout BulkOutcome,
                      consecutiveFailures: inout Int) -> Bool {
        switch step {
        case .completed:
            consecutiveFailures = 0
            outcome.completed += 1
        case .alreadySpent:
            // Not a failure: the pass asked, got an answer, and there is
            // nothing left to do for this lock. It must reset the run for the
            // same reason a completion does.
            consecutiveFailures = 0
            outcome.alreadySpent += 1
        case .awaitingSync:
            // The network took it; only the read-back is missing. Also not a
            // failure, so it resets the run too — a batch of these must not
            // trip the stop rule.
            consecutiveFailures = 0
            outcome.awaitingSync += 1
        case .cancelled:
            outcome.cancelled = true
            return true
        case .failed(let message):
            outcome.failed += 1
            consecutiveFailures += 1
            if outcome.firstFailureMessage == nil {
                outcome.firstFailureMessage = message
            }
            if consecutiveFailures >= consecutiveFailureLimit {
                outcome.stoppedAfterRepeatedFailures = true
                return true
            }
        }
        return false
    }

    /// Every tracked funding lock still worth retrying: a status that is not a
    /// finished transfer, a route this service handles, and no recorded
    /// already-spent probe. This is the same predicate the per-transaction
    /// action uses, applied to the whole snapshot.
    ///
    /// Restoring a wallet turns every shielded funding lock into
    /// `RecoveredFromChain` at once, so this is routinely dozens of entries —
    /// which is exactly why they need one action rather than one tap each.
    static func pendingRecoveries() -> [PendingRecovery] {
        // The snapshot spans every wallet whose rows live in this container, so
        // the active wallet's id is the first filter: resuming another wallet's
        // outpoint fails with "not tracked by this wallet", and a batch of them
        // reports as a network problem it never was.
        guard let activeWalletId = SwiftDashSDKHost.shared.wallet?.walletId else { return [] }
        return ShieldedTxLookup.shared.allEntries().compactMap { entry in
            guard entry.info.walletId == activeWalletId,
                  entry.info.fundingTypeRaw == bulkFundingTypeRaw,
                  bulkStatusAllowsRecovery(entry.info.statusRaw),
                  let txidWire = txidWire(fromDisplayHex: entry.txidHex),
                  !AssetLockProbeStore.shared.contains(txidWire)
            else { return nil }
            return PendingRecovery(
                txidWire: txidWire,
                vout: entry.info.vout,
                fundingTypeRaw: entry.info.fundingTypeRaw)
        }
    }

    /// Resume every pending lock, gating authentication ONCE for the whole
    /// batch rather than per lock — dozens of PIN prompts is not a flow. The
    /// batch stops early only on an auth cancel; a single lock's failure is
    /// counted and the pass continues, because the locks are independent and
    /// one unreachable outpoint should not strand the rest.
    ///
    /// `progress` is called on the main actor after each lock with the number
    /// finished so far and the total.
    func recoverAll(_ pending: [PendingRecovery],
                    progress: @MainActor (Int, Int) -> Void = { _, _ in }) async -> BulkOutcome {
        var outcome = BulkOutcome()
        guard !pending.isEmpty else { return outcome }

        // One gate for the batch: authorize here, then run every resume inside
        // `preauthorized`, whose task-local suppresses only the second prompt
        // for exactly this work — dozens of PIN prompts is not a flow. Any
        // other entry point still gates for itself.
        do {
            try await DWIdentityAuthorizer().authorize()
        } catch DWIdentityAuthorizer.AuthError.cancelled {
            outcome.cancelled = true
            return outcome
        } catch {
            // Authentication can also time out or fail outright. Reporting
            // that as "Cancelled." blames the user for something they did not
            // do and hides the reason, so it gets its own state.
            outcome.authFailureMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            DWLogger.log("LOCK-RETRY bulk aborted — authentication failed: \(outcome.authFailureMessage ?? "")")
            return outcome
        }

        let result = await DWIdentityAuthorizer.preauthorized { [self] in
            await runRecoveries(pending, into: outcome, progress: progress)
        }
        // Once for the pass. Each `retry` suppressed its own refresh, and
        // nothing between iterations reads the lookup.
        await ShieldedTxLookup.shared.refresh(reason: "asset-lock-recovery-completed")
        return result
    }

    private func runRecoveries(_ pending: [PendingRecovery],
                               into initial: BulkOutcome,
                               progress: @MainActor (Int, Int) -> Void) async -> BulkOutcome {
        var outcome = initial

        var consecutiveFailures = 0
        DWLogger.log("LOCK-RETRY bulk start count=\(pending.count)")

        for (index, item) in pending.enumerated() {
            let txidDisplay = String(Data(item.txidWire.reversed())
                .map { String(format: "%02x", $0) }.joined().prefix(16))
            do {
                let result = try await retry(
                    fundingTypeRaw: item.fundingTypeRaw,
                    txidWire: item.txidWire,
                    vout: item.vout,
                    // One refresh for the pass, in `recoverAll`. Per item it is
                    // a full lookup rebuild on top of the one `resumeAssetLock`
                    // already does, and nothing between iterations reads it.
                    refreshLookup: false)
                let step: BulkStep
                switch result {
                case .completed: step = .completed
                case .completionUnconfirmed: step = .alreadySpent
                case .submittedAwaitingSync: step = .awaitingSync
                }
                Self.apply(step, to: &outcome, consecutiveFailures: &consecutiveFailures)
                DWLogger.log("LOCK-RETRY bulk \(index + 1)/\(pending.count) \(txidDisplay)… -> \(result)")
            } catch DWIdentityAuthorizer.AuthError.cancelled {
                Self.apply(.cancelled, to: &outcome, consecutiveFailures: &consecutiveFailures)
                DWLogger.log("LOCK-RETRY bulk cancelled at \(index + 1)/\(pending.count)")
                return outcome
            } catch {
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                let stop = Self.apply(.failed(message), to: &outcome, consecutiveFailures: &consecutiveFailures)
                // File logger, not just OSLog: a bulk pass that fails is
                // exactly what a diagnostic export needs to carry.
                DWLogger.log("LOCK-RETRY bulk \(index + 1)/\(pending.count) \(txidDisplay)… FAILED: \(message)")
                Self.logger.error("🔁 LOCK-RETRY :: bulk item failed: \(String(describing: error), privacy: .public)")

                if stop {
                    DWLogger.log("LOCK-RETRY bulk stopped after \(consecutiveFailures) consecutive failures")
                    progress(index + 1, pending.count)
                    return outcome
                }
            }
            progress(index + 1, pending.count)
        }

        DWLogger.log("LOCK-RETRY bulk finished completed=\(outcome.completed) alreadySpent=\(outcome.alreadySpent) awaitingSync=\(outcome.awaitingSync) failed=\(outcome.failed)")
        Self.logger.info("🔁 LOCK-RETRY :: bulk finished completed=\(outcome.completed, privacy: .public) alreadySpent=\(outcome.alreadySpent, privacy: .public) awaitingSync=\(outcome.awaitingSync, privacy: .public) failed=\(outcome.failed, privacy: .public)")
        return outcome
    }

    /// Display-order hex ("as shown in the UI") to the 32-byte wire-order txid
    /// the resume entry points expect. Mirrors
    /// `ShieldedTransferCoordinator.parseOutPoint`'s reversal.
    ///
    /// Not private: a byte-order slip here makes every bulk resume fail with
    /// "not tracked by this wallet" and the pass reports a network problem it
    /// never had, so it is pinned by a test.
    static func txidWire(fromDisplayHex hex: String) -> Data? {
        guard hex.count == 64 else { return nil }
        var display = Data(capacity: 32)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            display.append(byte)
            idx = next
        }
        return Data(display.reversed())
    }

    private static func coreToPlatformRecipientAmountDuffs(
        txidWire: Data,
        vout: UInt32
    ) throws -> UInt64 {
        guard txidWire.count == 32,
              let container = SwiftDashSDKHost.shared.modelContainer,
              let reserveCredits = CoreToPlatformAmountPolicy.currentReserveCredits
        else { throw RecoveryError.notReady }

        var outPoint = Data(txidWire)
        var voutLittleEndian = vout.littleEndian
        withUnsafeBytes(of: &voutLittleEndian) { outPoint.append(contentsOf: $0) }
        let outPointHex = PersistentAssetLock.encodeOutPoint(rawBytes: outPoint)
        let descriptor = FetchDescriptor<PersistentAssetLock>(
            predicate: #Predicate<PersistentAssetLock> { row in
                row.outPointHex == outPointHex
            })

        guard let lock = try container.mainContext.fetch(descriptor).first,
              lock.amountDuffs > 0
        else { throw RecoveryError.unsupportedRoute }

        let lockValueDuffs = UInt64(lock.amountDuffs)
        let reserveDuffs = CoreToPlatformAmountPolicy.reserveDuffs(
            reserveCredits: reserveCredits)
        guard lockValueDuffs > reserveDuffs else {
            throw RecoveryError.unsupportedRoute
        }
        return lockValueDuffs - reserveDuffs
    }

    /// Identity top-up resume: the lock's credit output funds the
    /// wallet's own identity — the only identity this app tops up.
    /// `consumeInvitationVoucher` stays false: a generic retry surface
    /// must never silently consume an invitation lock (the SDK resolver
    /// refuses them).
    private func retryIdentityTopUp(txidWire: Data, vout: UInt32) async throws {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.error("🔁 LOCK-RETRY :: top-up aborted — no active wallet")
            throw RecoveryError.notReady
        }
        guard let identityId = DWCurrentUserIdentityInfo.shared.identityId else {
            Self.logger.error("🔁 LOCK-RETRY :: top-up aborted — wallet has no identity")
            throw RecoveryError.noIdentity
        }
        try await DWIdentityAuthorizer().authorize()
        _ = try await wallet.resumeTopUpWithAssetLock(
            identityId: identityId,
            outPointTxid: txidWire,
            outPointVout: vout)
        DWCurrentUserIdentityInfo.shared.refreshFromSDK()
    }

    /// Map the transfer coordinator's terminal phase to thrown errors.
    /// `Phase.failed` carries only the display text, so the PIN-cancel is
    /// recognized from the coordinator's typed `lastFailure` — never from
    /// its localized description — and rethrown as `AuthError.cancelled`
    /// so callers keep one cancel contract.
    private static func checkTerminalPhase(_ coordinator: ShieldedTransferCoordinator) throws {
        guard case .failed(let message) = coordinator.phase else { return }
        if let failure = coordinator.lastFailure as? ShieldedTransferCoordinator.CoordinatorError,
           case .authCancelled = failure {
            throw DWIdentityAuthorizer.AuthError.cancelled
        }
        throw RecoveryError.failed(message)
    }
}
