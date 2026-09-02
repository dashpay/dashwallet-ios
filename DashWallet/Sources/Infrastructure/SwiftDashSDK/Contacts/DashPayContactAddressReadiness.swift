//
//  DashPayContactAddressReadiness.swift
//  DashWallet
//
//  Copyright © 2026 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License;
//  you may not use this file except in compliance with the License.
//

#if DASHPAY

import Foundation
import OSLog
import SwiftDashSDK

/// Hold Core SPV until the wallet's DashPay contact addresses exist.
///
/// A contact's DIP-15 payment addresses are derived from its contact account,
/// and an address the wallet is not watching when the compact-filter scan
/// passes its funding height produces no transaction at all. Bringing identity,
/// contacts and contact accounts up first means the very first filter set
/// already covers them.
///
/// The sequence itself — including the discovery retry policy and the budget —
/// lives in the SDK (`PlatformWalletManager.startWalletSubsystems`), so iOS and
/// Android share one implementation and one set of tests. This file is the call
/// site and its logging; it deliberately holds no ordering logic of its own.
///
/// `reconcile_dashpay_rescan` (DIP-15 §12.6) stays load-bearing regardless:
/// contacts established later in a session, or on a later day, always arrive
/// after the scan. This removes the restore case from its workload, not the
/// mechanism.
@MainActor
enum DashPayContactAddressReadiness {
    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.dashpay-readiness")

    /// Run the pre-SPV sequence. Never throws: Core sync is the wallet's
    /// primary function and a Platform outage must not be able to leave the
    /// user without a balance. Whatever is not ready in time is left to the
    /// DIP-15 rescan — the same fallback that applied before this existed.
    static func awaitReady(
        manager: PlatformWalletManager,
        wallet: ManagedPlatformWallet,
        network: Network
    ) async {
        do {
            let outcome = try await manager.startWalletSubsystems(wallet: wallet)
            log(outcome, network: network)
        } catch {
            logger.warning(
                "👥 DP-READY :: bring-up failed; starting SPV anyway: \(String(describing: error), privacy: .public)")
        }
    }

    private static func log(_ outcome: WalletStartupOutcome, network: Network) {
        let seconds = String(format: "%.1f", outcome.elapsed)

        switch outcome.status {
        case .ready:
            logger.info(
                """
                👥 DP-READY :: ready for SPV in \(seconds, privacy: .public)s \
                scans=\(outcome.discoveryAttempts, privacy: .public) \
                drained=\(outcome.contactAccountsDrained, privacy: .public)
                """)
        case .noIdentity:
            logger.info(
                "👥 DP-READY :: no identity for this seed; nothing to prepare before SPV")
        case .partialNoIdentity:
            // Not an error: Platform was unreachable, so the question is still
            // open and the next runtime start asks again.
            logger.warning(
                """
                👥 DP-READY :: could not reach Platform in \(seconds, privacy: .public)s \
                after \(outcome.discoveryAttempts, privacy: .public) scan(s); \
                starting SPV, identity recovery retries on the next start
                """)
        case .partialAccountsPending:
            logger.warning(
                """
                👥 DP-READY :: \(outcome.contactAccountsPending, privacy: .public) contact \
                account build(s) still queued after \(seconds, privacy: .public)s; \
                starting SPV, the DIP-15 rescan will backfill
                """)
        case .discoveryFailed:
            // A local wallet/persistence fault, not the network. Logged at
            // error because unlike every other outcome here, nothing in this
            // session or the next will clear it on its own.
            logger.error(
                """
                👥 DP-READY :: identity discovery failed locally after \
                \(seconds, privacy: .public)s; starting SPV without DashPay state
                """)
        case .seedBindingUnverified:
            // The signer handed to the call belongs to a different wallet, so
            // the drain derived nothing rather than write contact addresses
            // from the wrong seed. A rerun with the right signer completes the
            // work, which stays queued — hence warning, not error.
            logger.warning(
                """
                👥 DP-READY :: contact crypto could not verify this wallet's seed \
                after \(seconds, privacy: .public)s; starting SPV, contact accounts \
                stay queued for a run with the matching signer
                """)
        case .identityScanIncomplete:
            // Every later step ran for the identity that is known, but the
            // gap-limit scan left indices unanswered, so the identity set is
            // not established. The verdict stays on record and the next launch
            // re-scans instead of taking the warm shortcut.
            logger.warning(
                """
                👥 DP-READY :: identity scan left indices unanswered after \
                \(seconds, privacy: .public)s \
                scans=\(outcome.discoveryAttempts, privacy: .public); \
                starting SPV, the next start re-scans
                """)
        }
    }
}

#endif
