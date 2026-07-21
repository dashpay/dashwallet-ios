//
//  SwiftDashSDKWalletWiper.swift
//  DashWallet
//
//  Wipes SwiftDashSDK wallet state — full per-wallet deletion (SwiftData
//  rows incl. PersistentTransaction, Rust manager state, and Keychain
//  material) via PlatformWalletManager.deleteWallet when DashSync's wipe
//  flow fires the DWWillWipeWalletNotification. Hooks NotificationCenter once at app
//  launch — covers all 5 user-facing wipe entry points (Settings →
//  Reset Wallet, lock screen emergency wipe, legacy PIN reset, etc.)
//  because they all funnel through `[DWEnvironment clearAllWalletsAndRemovePin:]`,
//  which posts the notification before it wipes.
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

/// Serializes full-wallet wipes and provides a FIFO barrier for callers that
/// must not continue while a wipe is still mutating Keychain/runtime state.
///
/// `NotificationCenter` delivers `DWWillWipeWalletNotification` synchronously,
/// so enqueueing the wipe from its observer and then enqueueing a barrier from
/// the caller guarantees the barrier runs after that wipe.
final class WalletWipeSerialExecutor {
    private let queue: DispatchQueue
    private var lastWipeSucceeded = true

    init(label: String = "org.dashfoundation.dash.wallet-wiper") {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func enqueue(_ operation: @escaping () -> Bool) {
        queue.async {
            self.lastWipeSucceeded = operation()
        }
    }

    func notifyWhenIdle(
        on completionQueue: DispatchQueue = .main,
        completion: @escaping (Bool) -> Void
    ) {
        queue.async {
            let succeeded = self.lastWipeSucceeded
            completionQueue.async {
                completion(succeeded)
            }
        }
    }
}

enum SwiftDashSDKWalletDeletionError: LocalizedError {
    case managerUnavailable

    var errorDescription: String? {
        switch self {
        case .managerUnavailable:
            return NSLocalizedString(
                "The wallet manager is not available. Please try again.",
                comment: "Wallets")
        }
    }
}

private final class WalletWipeResultAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var failureCount = 0

    func recordFailure() {
        lock.lock()
        failureCount += 1
        lock.unlock()
    }

    var succeeded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failureCount == 0
    }
}

@objc(DWSwiftDashSDKWalletWiper)
final class SwiftDashSDKWalletWiper: NSObject {

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.wallet-wiper")

    // MARK: - Notification name

    /// `DWWillWipeWalletNotification` posted by `[DWEnvironment
    /// clearAllWalletsAndRemovePin:]` BEFORE the actual wipe runs.
    /// Referenced by string literal here so this file has zero DashSync
    /// (or DWEnvironment) imports.
    private static let wipeNotificationName = NSNotification.Name("DWWillWipeWalletNotification")

    // MARK: - Observer keepalive

    /// Strong-ref keepalive for the observer token. Without this, the
    /// closure-based observer would be eligible for deallocation and
    /// would silently stop firing.
    private static var observerToken: NSObjectProtocol?
    private static let wipeExecutor = WalletWipeSerialExecutor()

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
            wipeExecutor.enqueue {
                performWipe()
            }
        }
        logger.info("registered DWWillWipeWalletNotification observer")
    }

    /// Invoke `completion` on the main queue with the last queued wipe's result
    /// after every wipe enqueued before this call has finished. The reinstall
    /// Delete flow uses this barrier before entering app root: PIN removal is
    /// synchronous, while SDK mnemonic/runtime deletion happens on
    /// `wipeExecutor`.
    @objc(waitForPendingWipeWithCompletion:)
    static func waitForPendingWipe(completion: @escaping (Bool) -> Void) {
        wipeExecutor.notifyWhenIdle(completion: completion)
    }

    // MARK: - Background wipe body

    /// The actual wipe body. Runs on a background `DispatchQueue` —
    /// uses keychain-backed storage only, so it has no `@MainActor`
    /// requirements. Total cost ~10–50 ms (much faster than the
    /// migrator's create path because there's no PBKDF2 or FFI work).
    ///
    /// Idempotent. Reports failure when enumeration or any per-wallet SDK
    /// deletion fails, leaving runtime/registry state available for retry.
    private static func performWipe() -> Bool {
        let startedAt = ContinuousClock.now

        // Enumerate every wallet that still has stored material BEFORE any
        // deletion runs. Once a deletion succeeds its mnemonic is gone, so a
        // retry naturally enumerates only the wallets that still need work.
        let storage = WalletStorage()
        let walletIds: [Data]
        do {
            walletIds = try storage.listWalletIdsWithMnemonic()
        } catch {
            logger.error("failed to enumerate wallets: \(String(describing: error), privacy: .public)")
            return false
        }

        // Full SwiftDashSDK wipe per wallet while the host-owned manager is
        // still alive (`handleWalletWiped()` below tears it down). This is what
        // actually clears the SwiftData store — `PersistentTransaction` /
        // `PersistentTxo` / identities / accounts — alongside the Rust
        // manager-side state and per-identity Keychain items. Mirrors the SDK
        // example app's `WalletDetailView.deleteWallet()`. Must run BEFORE the
        // teardown: the manager is dropped in `host.stop()`, and the
        // `PersistentWallet` row (needed for the identity/account cascade) is
        // deleted by `fullReset(forWipe:)`. A successful SDK deletion removes
        // that wallet's Keychain mnemonic, so no separate mnemonic-delete loop
        // follows.
        guard deleteWalletsFromSDK(walletIds) else {
            let elapsed = startedAt.duration(to: .now)
            logger.error(
                "wallet wipe failed after \(String(describing: elapsed), privacy: .public); preserving runtime and registry for retry")
            return false
        }

        // The SDK wallet deletion is now known to have succeeded for every
        // wallet. Clear app-owned global/per-wallet remnants only at this
        // commit point, so a failed wipe preserves a coherent retry state.
        // These stores use UserDefaults + locks and are safe on this queue.
        CoinJoinRecovery.shared.resetForWipe()
        CoinJoinWithdrawalStore.shared.resetForWipe()
        ShieldedWithdrawalStore.shared.resetForWipe()
        SPVChainResyncMarker.resetForWipe()
        CrowdNodeDefaults.shared.resetForWipe()

        // Clear the per-network active-wallet registry. The wipe removes ALL
        // wallets (mnemonics are network-agnostic — one keychain entry backs a
        // wallet on every network), so every network's recorded active id now
        // points at nothing. Phase 0's `resolveActiveWallet` fallback would
        // mask a stale id, but clearing it keeps the registry honest — a
        // wallet created afterwards resolves as `firstWallet` and re-pins
        // itself rather than briefly matching a dead id. UserDefaults-only, so
        // safe from this background queue.
        WalletEnvironment.setActiveWalletId(nil, for: .mainnet)
        WalletEnvironment.setActiveWalletId(nil, for: .testnet)

        let elapsed = startedAt.duration(to: .now)
        logger.info(
            "wiped \(walletIds.count) wallet(s) from SwiftDashSDK in \(String(describing: elapsed), privacy: .public)")

        // Tear down the app-owned runtime now that all wallet material is
        // gone. This stops BLAST/SPV, drops the host-owned manager/wallet, and
        // clears published wallet state. We do NOT delete public chain data;
        // leaving it lets the next wallet on the same device skip an expensive
        // resync.
        SwiftDashSDKWalletRuntime.handleWalletWiped()
        return true
    }

    /// Run the manager's synchronous full deletion for each wallet. The
    /// serial wipe executor waits on this semaphore while the manager-owned
    /// deletion runs on MainActor, matching SwiftDashSDK's synchronous API.
    private static func deleteWalletsFromSDK(_ walletIds: [Data]) -> Bool {
        let finished = DispatchSemaphore(value: 0)
        let result = WalletWipeResultAccumulator()
        Task { @MainActor in
            for walletId in walletIds {
                do {
                    try deleteWalletFromSDK(walletId)
                } catch {
                    result.recordFailure()
                    let walletLabel = walletId.prefix(4)
                        .map { String(format: "%02x", $0) }
                        .joined()
                    logger.error(
                        "deleteWallet failed for \(walletLabel, privacy: .public)…: \(String(describing: error), privacy: .public)")
                }
            }
            finished.signal()
        }
        finished.wait()
        return result.succeeded
    }

    /// Full per-wallet SwiftDashSDK deletion of a single wallet: the Rust
    /// manager state + this wallet's SwiftData rows and Keychain mnemonic via
    /// `PlatformWalletManager.deleteWallet(walletId:)`. The app-side cleanup
    /// runs only after that complete SDK operation succeeds. On failure the
    /// error is propagated and no additional destructive cleanup runs.
    ///
    /// The single per-wallet deletion primitive shared by the full wipe
    /// (`deleteWalletsFromSDK`) and the Wallets screen's per-wallet Remove
    /// flow (`WalletsViewModel`) — one body, not a copy on each side
    /// (guardrail #1). Callers own their own registry/runtime bookkeeping
    /// (the wipe tears the runtime down; the remove flow rebinds via
    /// `switchWallet` before deleting the active wallet).
    @MainActor
    static func deleteWalletFromSDK(
        _ walletId: Data,
        deleteWallet: (@MainActor (Data) throws -> Void)? = nil,
        clearAppState: (@MainActor (Data) -> Void)? = nil
    ) throws {
        let deleteWallet = deleteWallet ?? { walletId in
            guard let manager = SwiftDashSDKHost.shared.manager else {
                throw SwiftDashSDKWalletDeletionError.managerUnavailable
            }
            try manager.deleteWallet(walletId: walletId)
        }

        do {
            try deleteWallet(walletId)
        } catch {
            logger.error("deleteWallet failed: \(String(describing: error), privacy: .public)")
            throw error
        }

        // Clear this wallet's per-wallet app-side state that lives outside the
        // SDK/SwiftData/Keychain teardown above: CrowdNode account state and the
        // CoinJoin withdrawal tag set are UserDefaults, keyed by walletId hex.
        // Done here (not in the UI) so BOTH the per-wallet Remove flow and the
        // full wipe's per-wallet loop clear them — one shared deletion primitive
        // (guardrail #1). Hex must match `WalletEnvironment.activeWalletIdHex`
        // (lowercase, %02x). Idempotent; UserDefaults-only, so thread-agnostic.
        if let clearAppState {
            clearAppState(walletId)
        } else {
            let walletIdHex = walletId.map { String(format: "%02x", $0) }.joined()
            CrowdNodeDefaults.shared.clearPerWalletKeys(forWalletIdHex: walletIdHex)
            CoinJoinWithdrawalStore.shared.clearForWallet(walletIdHex: walletIdHex)
            ShieldedWithdrawalStore.shared.clearForWallet(walletIdHex: walletIdHex)
        }
    }
}
