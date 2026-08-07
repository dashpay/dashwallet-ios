//
//  SwiftDashSDKWalletWiper.swift
//  DashWallet
//
//  Wipes SwiftDashSDK wallet state — full per-wallet deletion (SwiftData
//  rows incl. PersistentTransaction, Rust manager state, and Keychain
//  material) via PlatformWalletManager.deleteWallet. All app wipe entry points
//  call this app-owned boundary directly; no DashSync registry mirror or
//  notification trampoline remains.
//
//  The wipe-side concern lives separately from the create/import-side concerns in
//  SwiftDashSDKWalletCreator.swift, and from the upgrade-time concern
//  in SwiftDashSDKKeyMigrator.swift.
//

import Foundation
import OSLog
import SwiftDashSDK

/// Serializes full-wallet wipes and provides a FIFO barrier for callers that
/// must not continue while a wipe is still mutating Keychain/runtime state.
///
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
    case unrecognizedWalletNetwork

    var errorDescription: String? {
        switch self {
        case .managerUnavailable:
            return NSLocalizedString(
                "The wallet manager is not available. Please try again.",
                comment: "Wallets")
        case .unrecognizedWalletNetwork:
            return NSLocalizedString(
                "The wallet network could not be determined. Please try again.",
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

    private static let wipeExecutor = WalletWipeSerialExecutor()

    // MARK: - Public entry point

    /// Starts a full app/SDK-owned wipe. PIN removal is part of the successful
    /// wipe commit: a failed SDK deletion leaves both wallet material and its
    /// authentication state available for retry. Callers observe completion
    /// through `waitForPendingWipe`.
    @objc(wipeWalletRemovingPin:)
    static func wipeWallet(removingPin: Bool) {
        wipeExecutor.enqueue {
            performWipe(removingPin: removingPin)
        }
    }

    /// Invoke `completion` on the main queue with the last queued wipe's result
    /// after every wipe enqueued before this call has finished. UI flows use
    /// this barrier before navigating away from a deleting-wallet state.
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
    private static func performWipe(removingPin: Bool) -> Bool {
        let startedAt = ContinuousClock.now

        // Classify the global Keychain inventory by its network-derived wallet
        // id. Wallet ids and SwiftData stores are network-scoped even though a
        // mnemonic can be used on both networks; sending every id through the
        // current manager would silently delete the wrong Keychain row while
        // leaving the other network's persisted wallet behind.
        let storage = WalletStorage()
        let walletIdsByNetwork: [Network: Set<Data>]
        do {
            walletIdsByNetwork = try classifyStoredWalletIdsByNetwork(storage: storage)
        } catch {
            logger.error("failed to classify wallet inventory: \(String(describing: error), privacy: .public)")
            return false
        }

        // Delete each network through a manager configured with that network's
        // ModelContainer. This clears SwiftData, Rust state, identities, and
        // SDK-owned Keychain material together. The current network is handled
        // last so a failure preparing the inactive network leaves the live
        // wallet untouched.
        guard deleteWalletsFromSDK(walletIdsByNetwork) else {
            let elapsed = startedAt.duration(to: .now)
            logger.error(
                "wallet wipe failed after \(String(describing: elapsed), privacy: .public); preserving runtime and registry for retry")
            return false
        }

        // The SDK wallet deletion is now known to have succeeded for every
        // network. Clear every global app-owned store only at this commit
        // point, so a failed wipe preserves a coherent wallet,
        // authentication, metadata, and preferences state for retry.
        DispatchQueue.main.sync {
            if removingPin {
                AuthenticationService.shared.removePin()
            }
            App.shared.cleanUp()
            DWGlobalOptions.sharedInstance().restoreToDefaults()
            DWAppGroupOptions.sharedInstance().restoreToDefaults()
            CrowdNode.shared.resetForWipe()
        }

        // These stores use UserDefaults + locks and are safe on this queue.
        CoinJoinRecovery.shared.resetForWipe()
        CoinJoinWithdrawalStore.shared.resetForWipe()
        ShieldedWithdrawalStore.shared.resetForWipe()
        SPVChainResyncMarker.resetForWipe()
        // Without this a contested submission outlived the wallet that made it:
        // reset mid-vote, create a new wallet, and the new wallet reported the
        // old one's name as still in voting.
        DWContestedNameStatusService.resetForWipe()

        // Clear both network-scoped active-wallet registry entries only after
        // both network stores and the global SDK Keychain inventory are empty.
        WalletEnvironment.setActiveWalletId(nil, for: .mainnet)
        WalletEnvironment.setActiveWalletId(nil, for: .testnet)

        let elapsed = startedAt.duration(to: .now)
        logger.info(
            "wiped SwiftDashSDK wallets across mainnet/testnet in \(String(describing: elapsed), privacy: .public)")

        // Tear down the app-owned runtime now that all wallet material is
        // gone. This stops BLAST/SPV, drops the host-owned manager/wallet, and
        // clears published wallet state. We do NOT delete public chain data;
        // leaving it lets the next wallet on the same device skip an expensive
        // resync.
        SwiftDashSDKWalletRuntime.handleWalletWiped()
        return true
    }

    /// Match each SDK-owned Keychain wallet id to the network discriminant
    /// included in its deterministic id. An unknown id is a hard failure:
    /// guessing a manager could recreate the false-success/data-resurrection
    /// bug this classification exists to prevent.
    private static func classifyStoredWalletIdsByNetwork(
        storage: WalletStorage
    ) throws -> [Network: Set<Data>] {
        var result: [Network: Set<Data>] = [.mainnet: [], .testnet: []]

        for walletId in try storage.listWalletIdsWithMnemonic() {
            let mnemonic = try storage.retrieveMnemonic(for: walletId)
            var matchedNetwork: Network?

            for network in [Network.mainnet, .testnet] {
                let derivedId = try SwiftDashSDK.Wallet(
                    mnemonic: mnemonic,
                    network: network
                ).id
                if derivedId == walletId {
                    matchedNetwork = network
                    break
                }
            }

            guard let matchedNetwork else {
                throw SwiftDashSDKWalletDeletionError.unrecognizedWalletNetwork
            }
            result[matchedNetwork, default: []].insert(walletId)
        }

        return result
    }

    /// Run synchronous full deletion through the manager belonging to each
    /// network. Manager-persisted ids are unioned with the Keychain inventory
    /// so a previous partial wipe's seedless SwiftData wallet is removed too.
    private static func deleteWalletsFromSDK(
        _ storedWalletIdsByNetwork: [Network: Set<Data>]
    ) -> Bool {
        // `finished.wait()` below blocks this thread until the `@MainActor`
        // task signals it. On the main thread that task could never be
        // scheduled, so the wait would deadlock rather than fail.
        guard !Thread.isMainThread else {
            logger.error("Refusing synchronous wallet deletion on the main thread")
            return false
        }

        let finished = DispatchSemaphore(value: 0)
        let result = WalletWipeResultAccumulator()
        Task { @MainActor in
            let host = SwiftDashSDKHost.shared
            var networks: [Network] = [.mainnet, .testnet]
            if let current = host.runningNetwork,
               let currentIndex = networks.firstIndex(of: current) {
                networks.remove(at: currentIndex)
                networks.append(current)
            }

            for network in networks {
                do {
                    let manager = try host.managerForWipe(network: network)
                    var walletIds = Set(manager.wallets.keys)
                    walletIds.formUnion(storedWalletIdsByNetwork[network] ?? [])

                    for walletId in walletIds.sorted(by: {
                        $0.lexicographicallyPrecedes($1)
                    }) {
                        do {
                            try deleteWalletFromSDK(
                                walletId,
                                deleteWallet: { id in
                                    try manager.deleteWallet(walletId: id)
                                })
                        } catch {
                            result.recordFailure()
                            logDeletionFailure(error, walletId: walletId, network: network)
                        }
                    }
                } catch {
                    result.recordFailure()
                    logger.error(
                        "failed to prepare \(network.networkName, privacy: .public) manager for wipe: \(String(describing: error), privacy: .public)")
                }
            }

            do {
                let remaining = try WalletStorage().listWalletIdsWithMnemonic()
                if !remaining.isEmpty {
                    result.recordFailure()
                    logger.error(
                        "wallet wipe left \(remaining.count, privacy: .public) SDK mnemonic item(s); reporting failure")
                }
            } catch {
                result.recordFailure()
                logger.error(
                    "failed to verify empty SDK wallet inventory: \(String(describing: error), privacy: .public)")
            }

            finished.signal()
        }
        finished.wait()
        return result.succeeded
    }

    private static func logDeletionFailure(
        _ error: Error,
        walletId: Data,
        network: Network
    ) {
        let walletLabel = walletId.prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
        logger.error(
            "deleteWallet failed for \(network.networkName, privacy: .public)/\(walletLabel, privacy: .public)…: \(String(describing: error), privacy: .public)")
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
