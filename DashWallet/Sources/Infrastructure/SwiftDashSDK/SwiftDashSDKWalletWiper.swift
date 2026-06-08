//
//  SwiftDashSDKWalletWiper.swift
//  DashWallet
//
//  Wipes SwiftDashSDK wallet state — full per-wallet deletion (SwiftData
//  rows incl. PersistentTransaction, Rust manager state, and Keychain
//  material) via PlatformWalletManager.deleteWallet, plus a mnemonic
//  safety-net — when DashSync's wipe flow fires the
//  DWWillWipeWalletNotification. Hooks NotificationCenter once at app
//  launch — covers all 5 user-facing wipe entry points (Settings →
//  Reset Wallet, lock screen emergency wipe, legacy PIN reset, etc.)
//  because they all funnel through `[DWEnvironment clearAllWalletsAndRemovePin:]`
//  which posts the notification at DWEnvironment.m:104.
//
//  This file is intentionally decoupled from DashSync and from
//  dashwallet-ios's own DWEnvironment header — it references the
//  notification name as a plain string literal. The wipe-side concern
//  lives separately from the create/import-side concerns in
//  SwiftDashSDKWalletCreator.swift, and from the upgrade-time concern
//  in SwiftDashSDKKeyMigrator.swift.
//

import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKWalletWiper)
final class SwiftDashSDKWalletWiper: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-wiper")

    // MARK: - Notification name

    /// `DWWillWipeWalletNotification` posted by `[DWEnvironment
    /// clearAllWalletsAndRemovePin:]` at `DWEnvironment.m:104` BEFORE
    /// the actual wipe runs. Referenced by string literal here so this
    /// file has zero DashSync (or DWEnvironment) imports.
    private static let wipeNotificationName = NSNotification.Name("DWWillWipeWalletNotification")

    // MARK: - Observer keepalive

    /// Strong-ref keepalive for the observer token. Without this, the
    /// closure-based observer would be eligible for deallocation and
    /// would silently stop firing.
    private static var observerToken: NSObjectProtocol?

    // MARK: - Public entry point

    /// Register the wipe-mirror observer once at app launch.
    ///
    /// Idempotent — subsequent calls are no-ops. Call from
    /// `AppDelegate.application:didFinishLaunchingWithOptions:`
    /// alongside `[DWSwiftDashSDKKeyMigrator migrateIfNeeded]`.
    @objc(startObservingWipeNotification)
    static func startObservingWipeNotification() {
        guard observerToken == nil else { return }

        observerToken = NotificationCenter.default.addObserver(
            forName: wipeNotificationName,
            object: nil,
            queue: nil
        ) { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                performWipe()
            }
        }
        logger.info("registered DWWillWipeWalletNotification observer")
    }

    // MARK: - Background wipe body

    /// The actual wipe body. Runs on a background `DispatchQueue` —
    /// uses keychain-backed storage only, so it has no `@MainActor`
    /// requirements. Total cost ~10–50 ms (much faster than the
    /// migrator's create path because there's no PBKDF2 or FFI work).
    ///
    /// Idempotent. Never throws, never crashes; all errors swallowed
    /// to os.log.
    private static func performWipe() {
        // Clear app-level CoinJoin state that is NOT per-wallet-keyed and
        // therefore survives the SDK/SwiftData/Keychain teardown below. Done
        // FIRST so it runs on every wipe — including the enumeration-failure
        // early return — letting a wallet restored afterwards re-run the
        // one-time wide recovery scan and start with a clean withdrawal tag set.
        // Both touch only UserDefaults + an NSLock, so they're safe from this
        // background queue with no @MainActor hop (unlike deleteWalletsFromSDK).
        CoinJoinRecovery.shared.resetForWipe()
        CoinJoinWithdrawalStore.shared.resetForWipe()

        // Enumerate every wallet that still has stored material BEFORE any
        // deletion runs. Both the SDK wipe and the mnemonic safety-net below
        // consume this list, and once mnemonics are gone (or the runtime is
        // torn down) `listWalletIdsWithMnemonic()` would return empty.
        let storage = WalletStorage()
        let walletIds: [Data]
        do {
            walletIds = try storage.listWalletIdsWithMnemonic()
        } catch {
            logger.error("failed to enumerate wallets: \(String(describing: error), privacy: .public)")
            // Still tear down the runtime so the app doesn't keep a stale
            // wallet alive after a failed enumeration.
            SwiftDashSDKWalletRuntime.handleWalletWiped()
            return
        }

        // Full SwiftDashSDK wipe per wallet while the host-owned manager is
        // still alive (`handleWalletWiped()` below tears it down). This is what
        // actually clears the SwiftData store — `PersistentTransaction` /
        // `PersistentTxo` / identities / accounts — alongside the Rust
        // manager-side state and per-identity Keychain items. Mirrors the SDK
        // example app's `WalletDetailView.deleteWallet()`. Must run BEFORE the
        // teardown: the manager is dropped in `host.stop()`, and the
        // `PersistentWallet` row (needed for the identity/account cascade) is
        // deleted by `fullReset(forWipe:)`.
        deleteWalletsFromSDK(walletIds)

        // Safety net: ensure the seed is gone even if `deleteWallet` threw
        // before reaching its own mnemonic-delete step (e.g. the wallet was
        // never registered in the Rust manager). Idempotent — no-op on an
        // already-deleted mnemonic.
        for walletId in walletIds {
            try? storage.deleteMnemonic(for: walletId)
        }
        logger.info("wiped \(walletIds.count) wallet(s) from SwiftDashSDK")

        // Tear down the app-owned runtime now that all wallet material is
        // gone. This stops BLAST/SPV, drops the host-owned manager/wallet, and
        // clears published wallet state. We do NOT delete public chain data;
        // leaving it lets the next wallet on the same device skip an expensive
        // resync.
        SwiftDashSDKWalletRuntime.handleWalletWiped()
    }

    /// Run `PlatformWalletManager.deleteWallet(walletId:)` for each wallet.
    /// The manager is `@MainActor`-isolated, but `performWipe()` runs on a
    /// background `DispatchQueue`, so hop to main (or run inline if already
    /// there). Mirrors `HomeViewModel`'s main-thread trampoline pattern.
    private static func deleteWalletsFromSDK(_ walletIds: [Data]) {
        let work = {
            MainActor.assumeIsolated {
                guard let manager = SwiftDashSDKHost.shared.manager else {
                    logger.info("no live PlatformWalletManager; skipping SDK deleteWallet")
                    return
                }
                for walletId in walletIds {
                    do {
                        try manager.deleteWallet(walletId: walletId)
                    } catch {
                        logger.error("deleteWallet failed: \(String(describing: error), privacy: .public)")
                    }
                }
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync { work() }
        }
    }
}
