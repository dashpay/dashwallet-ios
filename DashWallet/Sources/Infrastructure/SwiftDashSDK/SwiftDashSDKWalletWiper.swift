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

    init(label: String = "org.dashfoundation.dash.wallet-wiper") {
        queue = DispatchQueue(label: label, qos: .userInitiated)
    }

    func enqueue(_ operation: @escaping () -> Void) {
        queue.async(execute: operation)
    }

    func notifyWhenIdle(
        on completionQueue: DispatchQueue = .main,
        completion: @escaping () -> Void
    ) {
        queue.async {
            completionQueue.async(execute: completion)
        }
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

    /// Invoke `completion` on the main queue after every wipe enqueued before
    /// this call has finished. The reinstall Delete flow uses this barrier
    /// before entering app root: PIN removal is synchronous, while SDK
    /// mnemonic/runtime deletion happens on `wipeExecutor`.
    @objc(waitForPendingWipeWithCompletion:)
    static func waitForPendingWipe(completion: @escaping () -> Void) {
        wipeExecutor.notifyWhenIdle(completion: completion)
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
        let startedAt = ContinuousClock.now

        // Clear app-level CoinJoin state that is NOT per-wallet-keyed and
        // therefore survives the SDK/SwiftData/Keychain teardown below. Done
        // FIRST so it runs on every wipe — including the enumeration-failure
        // early return — letting a wallet restored afterwards re-run the
        // one-time wide recovery scan and start with a clean withdrawal tag set.
        // Both touch only UserDefaults + an NSLock, so they're safe from this
        // background queue with no @MainActor hop (unlike deleteWalletsFromSDK).
        CoinJoinRecovery.shared.resetForWipe()
        CoinJoinWithdrawalStore.shared.resetForWipe()
        ShieldedWithdrawalStore.shared.resetForWipe()
        // Pending birth-height chain resyncs reference wallet rows and chain
        // data this wipe destroys; a stale marker would only wipe the next
        // wallet's fresh sync. UserDefaults-only, safe from this queue.
        SPVChainResyncMarker.resetForWipe()
        // CrowdNode state is per-wallet-keyed; the wipe destroys every wallet, so
        // clear every wallet's keys (the CrowdNode singleton's own
        // `DWWillWipeWallet` observer only resets the ACTIVE wallet's keys). Also
        // UserDefaults-only, safe from this background queue.
        CrowdNodeDefaults.shared.resetForWipe()

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
        // deleted by `fullReset(forWipe:)`. Each per-wallet delete also removes
        // that wallet's Keychain mnemonic (the safety-net step lives inside
        // `deleteWalletFromSDK`), so no separate mnemonic-delete loop follows.
        deleteWalletsFromSDK(walletIds)
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
    }

    /// Run the manager's asynchronous full deletion for each wallet. The
    /// serial wipe executor waits on this semaphore, while the expensive
    /// SwiftData work awaits off-main inside SwiftDashSDK. Only the manager's
    /// brief Rust/in-memory mutations execute on MainActor.
    private static func deleteWalletsFromSDK(_ walletIds: [Data]) {
        let finished = DispatchSemaphore(value: 0)
        Task { @MainActor in
            for walletId in walletIds {
                await deleteWalletFromSDK(walletId)
            }
            finished.signal()
        }
        finished.wait()
    }

    /// Full per-wallet SwiftDashSDK deletion of a single wallet: the Rust
    /// manager state + this wallet's SwiftData rows (via
    /// `PlatformWalletManager.deleteWallet(walletId:)`) and its Keychain
    /// mnemonic (via `WalletStorage().deleteMnemonic(for:)`). Both steps are
    /// idempotent — a no-op on an already-deleted wallet — and their failures
    /// are logged, not thrown, so a partial failure of one step doesn't block
    /// the other.
    ///
    /// The single per-wallet deletion primitive shared by the full wipe
    /// (`deleteWalletsFromSDK`) and the Wallets screen's per-wallet Remove
    /// flow (`WalletsViewModel`) — one body, not a copy on each side
    /// (guardrail #1). Callers own their own registry/runtime bookkeeping
    /// (the wipe tears the runtime down; the remove flow rebinds via
    /// `switchWallet` before deleting the active wallet).
    @MainActor
    static func deleteWalletFromSDK(_ walletId: Data) async {
        if let manager = SwiftDashSDKHost.shared.manager {
            do {
                try await manager.deleteWallet(walletId: walletId)
            } catch {
                logger.error("deleteWallet failed: \(String(describing: error), privacy: .public)")
            }
        } else {
            logger.info("no live PlatformWalletManager; skipping SDK deleteWallet")
        }
        // Safety net: ensure the seed is gone even if `deleteWallet` threw
        // before reaching its own mnemonic-delete step. Idempotent.
        try? WalletStorage().deleteMnemonic(for: walletId)

        // Clear this wallet's per-wallet app-side state that lives outside the
        // SDK/SwiftData/Keychain teardown above: CrowdNode account state and the
        // CoinJoin withdrawal tag set are UserDefaults, keyed by walletId hex.
        // Done here (not in the UI) so BOTH the per-wallet Remove flow and the
        // full wipe's per-wallet loop clear them — one shared deletion primitive
        // (guardrail #1). Hex must match `WalletEnvironment.activeWalletIdHex`
        // (lowercase, %02x). Idempotent; UserDefaults-only, so thread-agnostic.
        let walletIdHex = walletId.map { String(format: "%02x", $0) }.joined()
        CrowdNodeDefaults.shared.clearPerWalletKeys(forWalletIdHex: walletIdHex)
        CoinJoinWithdrawalStore.shared.clearForWallet(walletIdHex: walletIdHex)
        ShieldedWithdrawalStore.shared.clearForWallet(walletIdHex: walletIdHex)
    }
}
