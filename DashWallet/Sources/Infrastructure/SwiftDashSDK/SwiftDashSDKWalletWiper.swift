//
//  SwiftDashSDKWalletWiper.swift
//  DashWallet
//
//  Wipes SwiftDashSDK wallet state (encrypted seed, mnemonic, and runtime
//  wallet descriptor in Keychain) when DashSync's wipe flow fires the
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
        // 1) Delete the encrypted seed from WalletStorage. Already
        // idempotent — `WalletStorage.deleteSeed` accepts both
        // `errSecSuccess` and `errSecItemNotFound`
        // (per WalletStorage.swift:97).
        do {
            try WalletStorage().deleteSeed()
            logger.info("deleted encrypted seed from WalletStorage")
        } catch {
            logger.error("failed to delete seed: \(String(describing: error), privacy: .public)")
        }

        do {
            try WalletStorage().deleteMnemonic()
            logger.info("deleted mnemonic from WalletStorage")
        } catch {
            logger.error("failed to delete mnemonic: \(String(describing: error), privacy: .public)")
        }

        do {
            try SwiftDashSDKRuntimeWalletStore().delete()
            logger.info("deleted runtime wallet descriptor from Keychain")
        } catch {
            logger.error("failed to delete runtime wallet descriptor: \(String(describing: error), privacy: .public)")
        }

        // 2) Invalidate the in-memory wallet cache. The descriptor, mnemonic,
        // and seed were already deleted from keychain above, so the next
        // getWallet() call will fail — which is correct.
        SwiftDashSDKWalletProvider.shared.invalidate()

        // Tear down the SPV coordinator now that the wallet is wiped from
        // the keychain. Without this, the coordinator would
        // keep running its in-memory wallet against the now-orphaned chain
        // data dir until the next app restart. The user can still create or
        // recover a fresh wallet afterwards — SwiftDashSDKWalletCreator wakes
        // the coordinator back up on its own. Idempotent — no-op if already
        // stopped. We do NOT delete the per-network SPV chain data dir at
        // Documents/SwiftDashSDK/SPV/<network>/ — chain data is public and
        // leaving it lets the next wallet on the same device skip an
        // expensive resync.
        SwiftDashSDKSPVCoordinator.stop()

        // Clear the cached wallet balance so a wipe-then-recover or
        // wipe-then-create flow doesn't keep showing the previous wallet's
        // balance until the new wallet's first balance event arrives.
        // This is the only place we clear — `performStop` deliberately
        // preserves the last-seen value (matching how progress/syncProgress
        // are preserved across debug-screen Restart).
        SwiftDashSDKWalletState.shared.clearBalance()

        // Clear the cached transaction list alongside balance.
        SwiftDashSDKWalletState.shared.clearTransactions()
    }
}
