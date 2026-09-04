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

    /// What a resume that did not throw actually established.
    enum Outcome {
        /// The transfer finished on Platform during this call.
        case completed
        /// Platform reported the outpoint already spent. That report is not
        /// quorum-authenticated, so it proves the retry has nothing left to
        /// do without proving this particular transfer succeeded — say that
        /// rather than claiming a completion we did not witness.
        case completionUnconfirmed
    }

    /// Retry the transfer for the tracked lock at (`txidWire`, `vout`).
    /// PIN-gated (directly or inside the transfer coordinator). Throws
    /// `DWIdentityAuthorizer.AuthError.cancelled` when the user backs
    /// out of the PIN prompt — callers treat that as a non-error.
    /// Returns only after the resume ran to completion, which for a
    /// still-unlocked transaction includes the IS/CL wait.
    /// `sessionAuthSufficient` is for the bulk recovery pass, which gates the
    /// whole batch once instead of prompting per lock. Interactive callers
    /// leave it `false`.
    @discardableResult
    func retry(fundingTypeRaw: Int,
               txidWire: Data,
               vout: UInt32,
               sessionAuthSufficient: Bool = false) async throws -> Outcome {
        Self.logger.info("🔁 LOCK-RETRY :: type=\(fundingTypeRaw, privacy: .public) vout=\(vout, privacy: .public)")
        let outcome: Outcome
        switch fundingTypeRaw {
        case 1, 2:
            try await retryIdentityTopUp(txidWire: txidWire, vout: vout, sessionAuthSufficient: sessionAuthSufficient)
            outcome = .completed
        case 4, 5:
            // Both coordinator routes report their outcome through the
            // terminal phase rather than throwing, so the resume call and
            // the phase check stay one pair — a future route added here
            // can't forget the check.
            let coordinator = ShieldedTransferCoordinator()
            if fundingTypeRaw == 4 {
                await coordinator.resumeFundPlatform(
                    outPointTxidWire: txidWire, outPointVout: vout,
                    sessionAuthSufficient: sessionAuthSufficient)
            } else {
                await coordinator.resumeAssetLock(
                    outPointTxidWire: txidWire, outPointVout: vout,
                    sessionAuthSufficient: sessionAuthSufficient)
            }
            try Self.checkTerminalPhase(coordinator)
            // The coordinator parks an unauthenticated already-consumed
            // report at `.submittedUnconfirmed` instead of `.success`; carry
            // that distinction out rather than flattening it into "done".
            if coordinator.phase == .submittedUnconfirmed {
                // Platform reported this outpoint already spent. The SDK keeps
                // the lock at `RecoveredFromChain` (the report is not
                // quorum-authenticated), so record the probe here — otherwise
                // the answer dies with this call and every later launch offers
                // the same futile retry. Recorded at the service layer so the
                // single-row and bulk callers share it.
                AssetLockProbeStore.shared.record(txid: txidWire)
                outcome = .completionUnconfirmed
            } else {
                outcome = .completed
            }
        default:
            throw RecoveryError.unsupportedRoute
        }
        await ShieldedTxLookup.shared.refresh(reason: "asset-lock-recovery-completed")
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
        var failed = 0
        var cancelled = false
        /// First failure's message, surfaced so a run that mostly failed says
        /// WHY on screen instead of a bare count. Bulk failures land in OSLog,
        /// which a diagnostic export never captures (the gap ticket 32004
        /// found for sends), so the count alone left nothing to diagnose from.
        var firstFailureMessage: String?
        /// Set when the pass gave up early after repeated failures.
        var stoppedAfterRepeatedFailures = false

        var attempted: Int { completed + alreadySpent + failed }
    }

    /// Consecutive failures after which the pass stops. A network refusing one
    /// lock will refuse the next; grinding through dozens of proof builds
    /// against it wastes minutes and tells the user nothing new.
    private static let consecutiveFailureLimit = 3

    /// Every tracked funding lock still worth retrying: a status that is not a
    /// finished transfer, a route this service handles, and no recorded
    /// already-spent probe. This is the same predicate the per-transaction
    /// action uses, applied to the whole snapshot.
    ///
    /// Restoring a wallet turns every shielded funding lock into
    /// `RecoveredFromChain` at once, so this is routinely dozens of entries —
    /// which is exactly why they need one action rather than one tap each.
    static func pendingRecoveries() -> [PendingRecovery] {
        ShieldedTxLookup.shared.allEntries().compactMap { entry in
            guard TxDetailModel.statusAllowsRetry(entry.info.statusRaw),
                  supportsRetry(fundingTypeRaw: entry.info.fundingTypeRaw),
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

        // One gate for the batch. Everything below runs with
        // `sessionAuthSufficient`, which passes without UI only because this
        // succeeded; if the session is somehow not authenticated the per-lock
        // prompt still appears rather than silently proceeding.
        do {
            try await DWIdentityAuthorizer().authorize()
        } catch {
            outcome.cancelled = true
            return outcome
        }

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
                    sessionAuthSufficient: true)
                consecutiveFailures = 0
                switch result {
                case .completed: outcome.completed += 1
                case .completionUnconfirmed: outcome.alreadySpent += 1
                }
                DWLogger.log("LOCK-RETRY bulk \(index + 1)/\(pending.count) \(txidDisplay)… -> \(result)")
            } catch DWIdentityAuthorizer.AuthError.cancelled {
                outcome.cancelled = true
                DWLogger.log("LOCK-RETRY bulk cancelled at \(index + 1)/\(pending.count)")
                return outcome
            } catch {
                outcome.failed += 1
                consecutiveFailures += 1
                let message = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
                if outcome.firstFailureMessage == nil {
                    outcome.firstFailureMessage = message
                }
                // File logger, not just OSLog: a bulk pass that fails is
                // exactly what a diagnostic export needs to carry.
                DWLogger.log("LOCK-RETRY bulk \(index + 1)/\(pending.count) \(txidDisplay)… FAILED: \(message)")
                Self.logger.error("🔁 LOCK-RETRY :: bulk item failed: \(String(describing: error), privacy: .public)")

                if consecutiveFailures >= Self.consecutiveFailureLimit {
                    outcome.stoppedAfterRepeatedFailures = true
                    DWLogger.log("LOCK-RETRY bulk stopped after \(consecutiveFailures) consecutive failures")
                    progress(index + 1, pending.count)
                    return outcome
                }
            }
            progress(index + 1, pending.count)
        }

        DWLogger.log("LOCK-RETRY bulk finished completed=\(outcome.completed) alreadySpent=\(outcome.alreadySpent) failed=\(outcome.failed)")
        Self.logger.info("🔁 LOCK-RETRY :: bulk finished completed=\(outcome.completed, privacy: .public) alreadySpent=\(outcome.alreadySpent, privacy: .public) failed=\(outcome.failed, privacy: .public)")
        return outcome
    }

    /// Display-order hex ("as shown in the UI") to the 32-byte wire-order txid
    /// the resume entry points expect. Mirrors
    /// `ShieldedTransferCoordinator.parseOutPoint`'s reversal.
    private static func txidWire(fromDisplayHex hex: String) -> Data? {
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

    /// Identity top-up resume: the lock's credit output funds the
    /// wallet's own identity — the only identity this app tops up.
    /// `consumeInvitationVoucher` stays false: a generic retry surface
    /// must never silently consume an invitation lock (the SDK resolver
    /// refuses them).
    private func retryIdentityTopUp(txidWire: Data, vout: UInt32, sessionAuthSufficient: Bool = false) async throws {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.error("🔁 LOCK-RETRY :: top-up aborted — no active wallet")
            throw RecoveryError.notReady
        }
        guard let identityId = DWCurrentUserIdentityInfo.shared.identityId else {
            Self.logger.error("🔁 LOCK-RETRY :: top-up aborted — wallet has no identity")
            throw RecoveryError.noIdentity
        }
        try await DWIdentityAuthorizer().authorize(sessionAuthSufficient: sessionAuthSufficient)
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
