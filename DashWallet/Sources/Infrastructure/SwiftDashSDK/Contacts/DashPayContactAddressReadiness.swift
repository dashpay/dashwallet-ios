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
/// The sequence itself — including the discovery retry policy and the default
/// budget — lives in the SDK (`PlatformWalletManager.startWalletSubsystems`),
/// so iOS and Android share one implementation and one set of tests. This
/// file holds no ordering logic of its own; what it does decide, app-side, is
/// the budget handed to that sequence for a wallet generated on this device
/// (`StartupIdentityRecoveryPolicy`, keyed on `GeneratedWalletIdentityMarker`)
/// and the handoff of the outcome to `DWSameSeedIdentityRecoveryCoordinator`.
/// TODO(platform-wallet): carry "generated on this device" on the wallet
/// record so the short-budget probe moves into the shared Rust sequence.
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
        // A mnemonic generated on this device with no local identity gets a
        // short budget instead of the SDK default. That budget caps the
        // whole sequence, so it only serves as a probe: when the probe finds
        // an identity the marker is dropped, and if the probe completed its
        // scan but was cut short before the contact steps
        // (`probeNeedsFullRerun`) the sequence runs again with the default
        // budget — with a complete scan on record the SDK reuses the local
        // identity, so the second run spends its budget on the steps the
        // first one cut short. A probe whose own scan was cut off is not
        // re-run: the SDK would rescan from scratch, so that start leaves
        // the contact steps to the DIP-15 rescan and the next start asks
        // again. The final verdict goes to the same-seed recovery
        // coordinator, which decides whether its backstop still has
        // anything to do in this start (`StartupIdentityRecoveryPolicy`).
        let recovery = DWSameSeedIdentityRecoveryCoordinator.shared
        let walletId = wallet.walletId
        let container = SwiftDashSDKHost.shared.modelContainer
        // "First sight" is measured from the store, before the pass: the SDK
        // increments `discoveryAttempts` for a rescan of an identity already
        // on file too, so that counter cannot tell a new identity from a
        // re-confirmed one.
        let hadLocalIdentity = container.flatMap {
            DWSameSeedIdentityRecoveryCoordinator.hasLocalIdentity(walletId: walletId, modelContainer: $0)
        }
        // Reuses the reading above — this runs on the pre-SPV main-thread
        // path, so the store is not asked twice.
        let probeBudget = recovery.startupBudget(walletId: walletId, hasLocalIdentity: hadLocalIdentity)
        if let probeBudget {
            logger.info(
                "👥 DP-READY :: wallet generated on this device, no local identity — budget \(Int(probeBudget), privacy: .public)s")
        }
        do {
            var outcome = try await manager.startWalletSubsystems(wallet: wallet, budget: probeBudget)
            if let probeBudget, outcome.identityId != nil {
                // The seed owns an identity after all: the probe budget must
                // never apply to this wallet again, whether or not the probe
                // itself completed.
                GeneratedWalletIdentityMarker.clear(walletId: walletId)
                if StartupIdentityRecoveryPolicy.probeNeedsFullRerun(
                    identityFound: true,
                    // No slack on purpose: the SDK reports no "deadline
                    // fired" flag, so this is an approximation, and the two
                    // ways it can be wrong are not equal. A false positive
                    // costs a second full-budget sequence on the switch
                    // path; a false negative leaves the contact steps to the
                    // DIP-15 rescan, the fallback this pass documents
                    // anyway. Erring towards the cheap side.
                    // TODO(platform-wallet): expose a deadline-fired flag on
                    // `WalletStartupOutcome` and use it here.
                    budgetExhausted: outcome.elapsed >= probeBudget,
                    dashPaySyncRan: outcome.dashPaySyncRan,
                    contactAccountsPending: outcome.contactAccountsPending,
                    seedBindingUnverified: outcome.seedBindingUnverified,
                    identityScanIncomplete: outcome.identityScanIncomplete) {
                    log(outcome, network: network, phase: .probe)
                    logger.info(
                        "👥 DP-READY :: probe found an identity but was cut short — re-running with the default budget")
                    // The probe's identity is the start's answer unless the
                    // re-run also has one: a re-run that throws, or comes
                    // back without an identity (Platform went away, scan key
                    // unavailable), must not cost it.
                    do {
                        let rerun = try await manager.startWalletSubsystems(wallet: wallet)
                        if rerun.identityId != nil {
                            outcome = rerun
                        } else {
                            log(rerun, network: network, phase: .probe)
                            logger.warning(
                                "👥 DP-READY :: default-budget re-run lost the identity; keeping the probe verdict")
                        }
                    } catch {
                        logger.warning(
                            "👥 DP-READY :: default-budget re-run failed; keeping the probe verdict: \(String(describing: error), privacy: .public)")
                    }
                }
            }
            log(outcome, network: network, phase: .verdict)
            recovery.recordStartupDiscovery(
                status: outcome.status,
                identityId: outcome.identityId,
                // `hadLocalIdentity == false`, not `!= true`: an
                // inconclusive lookup must not be read as "the wallet had
                // none", which would claim a first sight and send every
                // later switch past the settled memo into the DPNS refresh.
                // Same conservative reading `startupBudget` uses.
                discoveredThisStart: outcome.identityId != nil && hadLocalIdentity == false,
                walletId: walletId,
                network: network)
        } catch {
            logger.warning(
                "👥 DP-READY :: bring-up failed; starting SPV anyway: \(String(describing: error), privacy: .public)")
        }
    }

    /// Which pass a DP-READY line describes: the start's verdict, or the
    /// short-budget probe that preceded a default-budget re-run. One start
    /// logs at most one `.verdict` line.
    private enum LogPhase {
        case verdict
        case probe
    }

    private static func log(_ outcome: WalletStartupOutcome, network: Network, phase: LogPhase) {
        let seconds = String(format: "%.1f", outcome.elapsed)
        let tag = phase == .probe ? "👥 DP-READY (probe) :: " : "👥 DP-READY :: "

        switch outcome.status {
        case .ready:
            logger.info(
                """
                \(tag, privacy: .public)ready for SPV in \(seconds, privacy: .public)s \
                scans=\(outcome.discoveryAttempts, privacy: .public) \
                drained=\(outcome.contactAccountsDrained, privacy: .public)
                """)
        case .noIdentity:
            logger.info(
                "\(tag, privacy: .public)no identity for this seed; nothing to prepare before SPV")
        case .partialNoIdentity:
            // Not an error: Platform (or the scan key) was unreachable, so the
            // question is still open. The same-seed recovery backstop asks
            // again in this start unless this wallet was already settled in
            // this process; every runtime start asks the SDK again.
            logger.warning(
                """
                \(tag, privacy: .public)could not reach Platform in \(seconds, privacy: .public)s \
                after \(outcome.discoveryAttempts, privacy: .public) scan(s); \
                starting SPV, the recovery backstop retries unless already settled this process
                """)
        case .partialAccountsPending:
            logger.warning(
                """
                \(tag, privacy: .public)\(outcome.contactAccountsPending, privacy: .public) contact \
                account build(s) still queued after \(seconds, privacy: .public)s; \
                starting SPV, the DIP-15 rescan will backfill
                """)
        case .discoveryFailed:
            // A local wallet/persistence fault, not the network. Logged at
            // error because a rescan cannot clear it; the same-seed recovery
            // backstop adopts whatever identity rows exist locally without
            // scanning, unless this wallet was already settled in this
            // process. The next runtime start asks the SDK again.
            logger.error(
                """
                \(tag, privacy: .public)identity discovery failed locally after \
                \(seconds, privacy: .public)s; starting SPV, the recovery backstop \
                adopts local rows without a scan
                """)
        case .seedBindingUnverified:
            // Never derive contact addresses when the available seed cannot be
            // proven to own this wallet. The queued work remains intact for a
            // later run with the correct Keychain mapping.
            logger.error(
                """
                \(tag, privacy: .public)wallet seed binding could not be verified; \
                starting SPV without deriving contact accounts
                """)
        case .identityScanIncomplete:
            // An identity was found (the backstop adopts it in this start),
            // but the scan left indices unanswered. The SDK records that
            // verdict so the next runtime start rescans instead of treating
            // the local identity set as complete.
            logger.warning(
                """
                \(tag, privacy: .public)identity scan incomplete after \
                \(outcome.discoveryAttempts, privacy: .public) scan(s) and \
                \(seconds, privacy: .public)s; starting SPV, the gap rescan \
                runs on the next start
                """)
        @unknown default:
            logger.warning(
                """
                \(tag, privacy: .public)unknown wallet startup status \
                \(outcome.status.rawValue, privacy: .public) after \
                \(seconds, privacy: .public)s; starting SPV without assuming \
                DashPay readiness
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
