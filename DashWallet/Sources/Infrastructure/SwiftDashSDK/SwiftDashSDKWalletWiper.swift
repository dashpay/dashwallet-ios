//
//  SwiftDashSDKWalletWiper.swift
//  DashWallet
//
//  Wipes SwiftDashSDK wallet state (encrypted seed in WalletStorage,
//  HDWallet SwiftData records) when DashSync's wipe flow fires the
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
import SwiftData
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
    /// uses the lowest-level public SwiftDashSDK API surface
    /// (`WalletStorage.deleteSeed`, `ModelContext.delete`) so it has
    /// no `@MainActor` requirements. Total cost ~10–50 ms (much faster
    /// than the migrator's create path because there's no PBKDF2 or
    /// FFI work — just two delete operations).
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

        // 2) Delete all HDWallet SwiftData records. dashwallet-ios is
        // single-wallet in practice, so this is 0 or 1 records — but
        // we delete ALL to handle any orphan accumulation from before
        // this PR shipped. Fresh background `ModelContext` against the
        // shared `ModelContainer` that `SwiftDashSDKContainer.warmUp()`
        // created at app launch. We deliberately do NOT call
        // `ModelContainerHelper.createContainer()` here — the SDK helper
        // fails CloudKit validation on entitled apps; see
        // SwiftDashSDKContainer.swift for the rationale.
        guard let modelContainer = SwiftDashSDKContainer.modelContainer else {
            logger.error("SwiftDashSDKContainer.modelContainer is nil — cannot delete HDWallet records")
            return
        }
        do {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<HDWallet>()
            let wallets = try context.fetch(descriptor)

            if wallets.isEmpty {
                logger.info("no HDWallet records to delete")
            } else {
                for wallet in wallets {
                    context.delete(wallet)
                }
                try context.save()
                logger.info("deleted \(wallets.count, privacy: .public) HDWallet record(s)")
            }
        } catch {
            logger.error("failed to delete HDWallet records: \(String(describing: error), privacy: .public)")
        }

        // Tear down the SPV coordinator now that the wallet is gone from
        // SwiftData and the keychain. Without this, the coordinator would
        // keep running its in-memory wallet against the now-orphaned chain
        // data dir until the next app restart. The user can still create or
        // recover a fresh wallet afterwards — SwiftDashSDKWalletCreator wakes
        // the coordinator back up on its own. Idempotent — no-op if already
        // stopped. We do NOT delete the per-network SPV chain data dir at
        // Documents/SwiftDashSDK/SPV/<network>/ — chain data is public and
        // leaving it lets the next wallet on the same device skip an
        // expensive resync.
        SwiftDashSDKSPVCoordinator.stop()
    }
}
