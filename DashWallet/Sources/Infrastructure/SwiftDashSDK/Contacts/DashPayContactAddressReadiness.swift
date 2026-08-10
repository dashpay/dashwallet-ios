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

/// Bring the wallet's DashPay contact addresses into existence *before* Core
/// SPV starts, so the very first compact-filter set already matches them.
///
/// The startup order this implements is identity → contacts → contact accounts
/// → core sync. Each step is a precondition of the next, and the last one is
/// the point: a contact's DIP-15 addresses are derived from the contact
/// account, and an address the wallet is not watching when the scan passes its
/// funding height produces no transaction at all.
///
/// Without this the wallet relied entirely on repair after the fact —
/// `reconcile_dashpay_rescan` (DIP-15 §12.6) lowers the SPV synced height once
/// a contact account finally appears, so the scan re-walks blocks it already
/// covered. That still runs, and still has to: contacts established later in a
/// session, or on a later day, always arrive after the scan. This only removes
/// the restore case from its workload, where it was doing the most work and
/// taking the longest to converge.
///
/// ## Why each step cannot be skipped
///
/// 1. **Identity.** No identity, no contacts — the DashPay sync has nothing to
///    enumerate.
/// 2. **Contacts.** `dashPaySyncNow()` fetches contact requests and *queues*
///    the account builds.
/// 3. **Contact accounts.** The queue is the part that surprises: the recurring
///    DashPay sweep runs unattended and holds no signer, so it can derive no
///    key material and only ever enqueues ("Deferred DashPay account build",
///    `contact_requests.rs`). The accounts — and therefore the addresses — come
///    into being only when a signer-present drain runs. Stopping after step 2
///    would order the sequence correctly and still start SPV with nothing extra
///    to watch.
@MainActor
enum DashPayContactAddressReadiness {
    /// Whole-sequence budget before Core SPV starts regardless.
    ///
    /// Core sync is the wallet's primary function and Platform is not; a
    /// Platform outage must not be able to leave the user without a balance.
    /// When the budget runs out the sequence gives up and SPV starts anyway,
    /// which is exactly the behaviour that shipped before this file existed —
    /// the fallback is the old path, never something worse.
    static let budget: TimeInterval = 20

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.dashpay-readiness")

    /// Run the pre-SPV sequence, returning when the contact accounts are ready
    /// or the budget is spent. Never throws: every step is best-effort, and a
    /// failure means SPV starts with whatever was ready in time.
    static func awaitReady(
        manager: PlatformWalletManager,
        wallet: ManagedPlatformWallet,
        network: Network
    ) async {
        let deadline = Date().addingTimeInterval(budget)
        let startedAt = Date()

        // 1. Identity. Reuses the same coordinator the runtime already owns,
        //    including its "discover only when the local store is empty" rule,
        //    so a warm launch costs nothing here.
        if let container = SwiftDashSDKHost.shared.modelContainer {
            await DWSameSeedIdentityRecoveryCoordinator.shared.recoverIfNeeded(
                wallet: wallet,
                modelContainer: container,
                network: network)
        }

        guard DWCurrentUserIdentityInfo.shared.identityId != nil else {
            logger.info("👥 DP-READY :: no identity; nothing to prepare before SPV")
            return
        }
        guard remaining(until: deadline) > 0 else {
            logBudgetSpent(after: "identity", startedAt: startedAt)
            return
        }

        // 2. Contacts. One explicit pass rather than waiting out the background
        //    loop's interval — the loop is started separately and keeps running
        //    afterwards.
        let syncedInTime = await bounded(by: deadline) {
            do {
                let summary = try await manager.dashPaySyncNow()
                logger.info(
                    "👥 DP-READY :: contact sync pass — \(summary.success, privacy: .public) ok, \(summary.errors, privacy: .public) failed")
            } catch {
                logger.warning(
                    "👥 DP-READY :: contact sync failed: \(String(describing: error), privacy: .public)")
            }
        }
        guard syncedInTime else {
            logBudgetSpent(after: "contacts", startedAt: startedAt)
            return
        }

        // 3. Contact accounts.
        await drainContactCrypto(manager: manager, wallet: wallet, deadline: deadline)

        let elapsed = Int(Date().timeIntervalSince(startedAt))
        logger.info("👥 DP-READY :: ready for SPV after \(elapsed, privacy: .public)s")
    }

    /// Complete the deferred contact crypto and wait for the queue to settle.
    ///
    /// Distinct from `SwiftDashSDKHost.unlockDashPayContactCrypto`, which
    /// watches for builds that appear *later* in a session and is deliberately
    /// long-lived; this is a bounded "drain what is queued right now" so SPV can
    /// start against a complete address set. The two cannot collide — the SDK
    /// refuses to stack a second drain on an in-flight one.
    private static func drainContactCrypto(
        manager: PlatformWalletManager,
        wallet: ManagedPlatformWallet,
        deadline: Date
    ) async {
        let walletId = wallet.walletId

        guard let pending = try? manager.pendingAccountBuildCount(for: walletId),
              pending > 0
        else {
            logger.info("👥 DP-READY :: no deferred contact account builds")
            return
        }

        logger.info(
            "👥 DP-READY :: draining \(pending, privacy: .public) deferred contact account build(s)")
        do {
            _ = try manager.unlockWalletFromKeychain(wallet)
        } catch {
            logger.warning(
                "👥 DP-READY :: unlock failed; starting SPV without contact accounts: \(String(describing: error), privacy: .public)")
            return
        }

        // The drain runs detached and publishes its progress through the
        // manager's 1 Hz status poll, so poll the same count rather than
        // inventing a second completion signal.
        while remaining(until: deadline) > 0 {
            try? await Task.sleep(for: .milliseconds(500))
            guard let left = try? manager.pendingAccountBuildCount(for: walletId) else { break }
            if left == 0 {
                logger.info("👥 DP-READY :: contact accounts built")
                return
            }
        }

        let stillPending = (try? manager.pendingAccountBuildCount(for: walletId)) ?? 0
        logger.warning(
            "👥 DP-READY :: budget spent with \(stillPending, privacy: .public) build(s) still queued; SPV starts anyway and the DIP-15 rescan will backfill")
    }

    private static func remaining(until deadline: Date) -> TimeInterval {
        deadline.timeIntervalSinceNow
    }

    /// Run `operation`, and stop waiting for it at `deadline`. Returns whether
    /// it finished in time.
    ///
    /// The operation is deliberately NOT cancelled when the wait expires. These
    /// are FFI calls carrying their own network timeouts, and cancelling a
    /// Swift task cannot abort one that is already inside Rust — a `cancel()`
    /// here would buy nothing but the illusion of one. The point is to free
    /// *this* caller: Core SPV has to start on time whatever Platform is doing,
    /// and a pass that lands late still lands, feeding the background loop that
    /// runs from here on.
    ///
    /// Everything stays on the main actor (`PlatformWalletManager` is
    /// `@MainActor`), so this polls a completion flag rather than racing inside
    /// a task group — a group would not return until its children did, which is
    /// precisely what must not happen here.
    private static func bounded(
        by deadline: Date,
        _ operation: @escaping @MainActor () async -> Void
    ) async -> Bool {
        final class CompletionFlag { var isDone = false }
        let flag = CompletionFlag()

        Task { @MainActor in
            await operation()
            flag.isDone = true
        }

        while !flag.isDone, remaining(until: deadline) > 0 {
            try? await Task.sleep(for: .milliseconds(200))
        }
        return flag.isDone
    }

    private static func logBudgetSpent(after step: String, startedAt: Date) {
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        logger.warning(
            "👥 DP-READY :: budget spent after \(step, privacy: .public) (\(elapsed, privacy: .public)s); starting SPV, the DIP-15 rescan will backfill")
    }
}

#endif
