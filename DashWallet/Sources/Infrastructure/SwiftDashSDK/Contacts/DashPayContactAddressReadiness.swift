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
        guard seedBindsToWallet(manager: manager, wallet: wallet) else { return }

        do {
            let outcome = try await manager.startWalletSubsystems(wallet: wallet)
            log(outcome, network: network)
        } catch {
            logger.warning(
                "👥 DP-READY :: bring-up failed; starting SPV anyway: \(String(describing: error), privacy: .public)")
        }
    }

    /// Confirm the Keychain seed actually owns this wallet before any
    /// mnemonic-derived work runs.
    ///
    /// `startWalletSubsystems` builds its own resolver and identity signer, so
    /// on a mismatched seed it would derive DIP-15 contact accounts from a
    /// mnemonic this wallet has already rejected — and a wrong receiving xpub
    /// is written once and never revisited, because the account's existence
    /// check keys on the contact pair rather than the xpub. The wallet would
    /// then watch addresses nobody pays to, silently.
    ///
    /// Verifying here rather than reading the published `seedMismatch` flag is
    /// deliberate: `SwiftDashSDKHost.loadPersistedWallet` schedules the unlock
    /// in a detached task and returns immediately, so that flag is racing this
    /// call and may not be set yet on the launch where it matters. The verify
    /// itself is marker-cached in the SDK — a match costs a string comparison,
    /// not a Keychain read.
    ///
    /// Returns `false` only for a proven mismatch. A watch-only wallet (no
    /// stored mnemonic) returns `true`: there is no seed to contradict, and
    /// the bring-up handles that case on its own.
    private static func seedBindsToWallet(
        manager: PlatformWalletManager,
        wallet: ManagedPlatformWallet
    ) -> Bool {
        do {
            _ = try manager.unlockWalletFromKeychain(wallet)
            return true
        } catch {
            logger.error(
                """
                👥 DP-READY :: the stored seed does not bind to this wallet; \
                skipping DashPay bring-up and starting SPV: \
                \(String(describing: error), privacy: .public)
                """)
            return false
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
        }
    }
}

#endif
