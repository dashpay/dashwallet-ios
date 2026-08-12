//
//  AssetLockRecoveryService.swift
//  DashWallet
//
//  User-initiated retry of a funding asset lock parked in a
//  non-terminal state — built/broadcast but never IS/CL-locked, or
//  locked on Core but whose Platform transition never landed (app
//  killed, network drop). Dispatches by funding type to the SDK's
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

    /// Retry the transfer for the tracked lock at (`txidWire`, `vout`).
    /// PIN-gated (directly or inside the transfer coordinator). Throws
    /// `DWIdentityAuthorizer.AuthError.cancelled` when the user backs
    /// out of the PIN prompt — callers treat that as a non-error.
    /// Returns only after the resume ran to completion, which for a
    /// still-unlocked transaction includes the IS/CL wait.
    func retry(fundingTypeRaw: Int, txidWire: Data, vout: UInt32) async throws {
        Self.logger.info("🔁 LOCK-RETRY :: type=\(fundingTypeRaw, privacy: .public) vout=\(vout, privacy: .public)")
        // All supported routes resume an existing asset lock and may enter the
        // SDK's IS/CL proof wait. Fail before auth while quorum data is absent.
        try AssetLockProofAvailability.shared.requireAllowed()
        switch fundingTypeRaw {
        case 1, 2:
            try await retryIdentityTopUp(txidWire: txidWire, vout: vout)
        case 4, 5:
            // Both coordinator routes report their outcome through the
            // terminal phase rather than throwing, so the resume call and
            // the phase check stay one pair — a future route added here
            // can't forget the check.
            let coordinator = ShieldedTransferCoordinator()
            if fundingTypeRaw == 4 {
                await coordinator.resumeFundPlatform(outPointTxidWire: txidWire, outPointVout: vout)
            } else {
                await coordinator.resumeAssetLock(outPointTxidWire: txidWire, outPointVout: vout)
            }
            try Self.checkTerminalPhase(coordinator)
        default:
            throw RecoveryError.unsupportedRoute
        }
        ShieldedTxLookup.shared.refresh()
        Self.logger.info("🔁 LOCK-RETRY :: completed type=\(fundingTypeRaw, privacy: .public)")
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
