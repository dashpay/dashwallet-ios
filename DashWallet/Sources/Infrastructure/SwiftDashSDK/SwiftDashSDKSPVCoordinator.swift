//
//  SwiftDashSDKSPVCoordinator.swift
//  DashWallet
//
//  Owns the SwiftDashSDK SPVClient lifecycle and exposes a Combine-friendly
//  interface for the dashwallet-ios UI to consume sync state.
//
//  Hard invariants — see DASHSYNC_KEY_MIGRATION.md and the SPV migration
//  plan in this PR series:
//    1. NEVER throws or crashes from public methods. All errors funnel into
//       `lastError` and `os.log` entries.
//    2. NEVER blocks the main thread. All SPV work runs on a dedicated
//       background queue. Published-state mutations are marshalled back to
//       the main queue so SwiftUI consumers see updates on the right thread.
//    3. Runtime readiness is owned externally by `SwiftDashSDKWalletRuntime`.
//       The coordinator assumes descriptor/network readiness was already
//       resolved before `start(with:completion:)` is called.
//    4. NEVER touches DashSync. SPV chain state lives under
//       `Documents/SwiftDashSDK/SPV/<network>/`, separate from DashSync's
//       Core Data store.
//    5. No force-unwraps, no `try!`, no `as!`.
//
//  This file owns the consumer side of `SPVClient` for dashwallet-ios. It
//  bypasses `WalletService.swift` (the SDK's internal SPV consumer with the
//  ~12 stub event handler bodies) so we can wire our own event handlers
//  directly to the UI without modifying SDK code. See SWIFT_SDK_SPV_GAPS.md
//  for the gap inventory this bypass implies.
//
//  Lower-level SPV engine used by `SwiftDashSDKWalletRuntime`. App lifecycle,
//  network selection, and descriptor readiness no longer live here.
//

import Combine
import Foundation
import OSLog
import SwiftDashSDK

@objc(DWSwiftDashSDKSPVCoordinator)
public final class SwiftDashSDKSPVCoordinator: NSObject, ObservableObject {

    // MARK: - Singleton

    /// Shared instance. Swift consumers observe published sync state through
    /// this singleton; runtime ownership lives in `SwiftDashSDKWalletRuntime`.
    public static let shared = SwiftDashSDKSPVCoordinator()

    // MARK: - Logging

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.spv-coordinator")

    // MARK: - Published state (Swift consumers via Combine)

    /// Aggregate sync progress (0.0 to 1.0). Updated on the main queue from
    /// `onProgressUpdate` events.
    @Published public private(set) var progress: Double = 0.0

    /// Current sync state (idle, waitingForConnections, syncing, synced, error).
    @Published public private(set) var state: SPVSyncState = .idle

    /// Latest header tip height as reported by the SPV client. 0 until the
    /// first sync event with a tip height fires.
    @Published public private(set) var tipHeight: UInt32 = 0

    /// Best height reported by connected peers — the target the client is
    /// catching up to. 0 until the first `onPeersUpdated` event fires.
    @Published public private(set) var bestPeerHeight: UInt32 = 0

    /// Number of peers currently connected. 0 until the first `onPeersUpdated`
    /// event fires.
    @Published public private(set) var connectedPeerCount: UInt32 = 0

    /// Last error message reported by the SPV client or by the coordinator's
    /// own start path. `nil` if no error has been reported.
    @Published public private(set) var lastError: String? = nil

    /// True iff `state == .synced`. Convenience for consumers that just want
    /// to know "are we done".
    @Published public private(set) var isComplete: Bool = false

    /// Latest full sync-progress snapshot. Carries per-phase detail
    /// (headers, filterHeaders, filters, blocks, masternodes, chainLocks,
    /// instantSend) for consumers that want more than the aggregate
    /// `progress` percentage.
    @Published public private(set) var syncProgress: SPVSyncProgress = .default()

    // MARK: - Private state

    /// Serial background queue for all SPV lifecycle operations. Never the
    /// main thread. Event handler callbacks may arrive on FFI threads — they
    /// route through `publish(_:)` which marshals to main.
    private let workQueue = DispatchQueue(
        label: "org.dashfoundation.dash.swift-sdk-spv-coordinator",
        qos: .userInitiated)

    /// The currently-active SPVClient. `nil` until `performStart()` finishes
    /// constructing it, or after `performStop()` runs. Mutated only on
    /// `workQueue`.
    private var client: SPVClient? = nil

    /// Coordinator lifecycle state — distinct from the SPV client's own
    /// `SPVSyncState`. Mutated only on `workQueue`.
    private enum LifecycleState {
        case notStarted
        case starting
        case running
        case stopped
        case failed
    }
    private var lifecycle: LifecycleState = .notStarted

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Public lifecycle (Obj-C accessible)

    /// Starts the coordinator with an explicit runtime wallet. Runtime
    /// ownership stays outside this type; the coordinator just manages the
    /// SPV client lifecycle and published sync state.
    func start(with wallet: HDWallet, completion: @escaping (Result<Void, Error>) -> Void) {
        workQueue.async {
            self.performStart(wallet: wallet, completion: completion)
        }
    }

    /// Stops the SPV client, destroys FFI handles, and resets published
    /// state to idle. Completion fires after the reset path finishes.
    func stop(lastError: String?, completion: (() -> Void)? = nil) {
        workQueue.async {
            self.performStop(lastError: lastError, completion: completion)
        }
    }

    @objc(stop)
    public static func stop() {
        shared.stop(lastError: nil, completion: nil)
    }

    // MARK: - Transaction support

    /// Returns the `WalletManager` from the running SPVClient.
    ///
    /// The wallet manager provides transaction-building APIs
    /// (`buildSignedTransaction`) that `SwiftDashSDKTransactionSender` uses.
    /// Throws if the SPV client is not running (e.g., runtime stopped or
    /// after a wipe).
    ///
    /// Thread-safe: `client` is set once during `performStart` and cleared
    /// only by `performStop`. Reads from any thread with a nil check are safe
    /// (same pattern as `WalletEventsHandler.onTransactionReceived`).
    func getWalletManager() throws -> WalletManager {
        guard let activeClient = client else {
            throw TransactionSenderError.spvNotRunning
        }
        return try activeClient.getWalletManager()
    }

    /// Broadcasts a signed transaction via the running SPVClient.
    ///
    /// Throws if the SPV client is not running or if the broadcast fails
    /// at the network layer.
    func broadcastTransaction(_ data: Data) throws {
        guard let activeClient = client else {
            throw TransactionSenderError.spvNotRunning
        }
        try activeClient.broadcastTransaction(data)
    }

    /// Errors surfaced by the transaction support methods.
    enum TransactionSenderError: LocalizedError {
        case spvNotRunning

        var errorDescription: String? {
            switch self {
            case .spvNotRunning:
                return "Wallet not ready — SPV client is not running"
            }
        }
    }

    // MARK: - Background lifecycle

    /// Heavy-lifting start path. Runs on `workQueue`. Constructs an
    /// `SPVClient` with our event handlers, imports the explicit runtime
    /// wallet bytes into the client's wallet manager, and kicks off
    /// `startSync()`.
    private func performStart(wallet migratedWallet: HDWallet, completion: @escaping (Result<Void, Error>) -> Void) {
        // Idempotent guard.
        switch lifecycle {
        case .starting, .running:
            Self.logger.info("🛰️ SPVCOORD :: start ignored — coordinator is already \(String(describing: self.lifecycle), privacy: .public)")
            completion(.success(()))
            return
        case .notStarted, .stopped, .failed:
            break
        }

        let appNetwork = migratedWallet.network
        let walletBytes = migratedWallet.serializedWalletBytes
        let expectedWalletId = migratedWallet.walletId

        Self.logger.info("🛰️ SPVCOORD :: starting SPV client for \(String(describing: appNetwork), privacy: .public), wallet bytes=\(walletBytes.count, privacy: .public)")

        lifecycle = .starting

        // Construct the per-handler classes. They hold weak references to
        // self and forward events through `publish(_:)`.
        let progressHandler = ProgressUpdateHandler(coordinator: self)
        let syncHandler = SyncEventsHandler(coordinator: self)
        let networkHandler = NetworkEventsHandler(coordinator: self)
        let walletHandler = WalletEventsHandler(coordinator: self)
        let errorHandler = ErrorEventsHandler(coordinator: self)

        let handlers = SPVEventHandlers(
            progress: progressHandler,
            sync: syncHandler,
            network: networkHandler,
            wallet: walletHandler,
            error: errorHandler)

        // Compute the per-network data directory.
        let dataDir: String
        do {
            dataDir = try ensureDataDirectory(for: appNetwork)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: failed to create SPV data directory: \(String(describing: error), privacy: .public)")
            lifecycle = .failed
            applyResetState(lastError: "Failed to create SPV data directory: \(error.localizedDescription)")
            completion(.failure(StartError.dataDirectory(error)))
            return
        }

        // Cold-sync from wallet birth height. Mainnet wallets imported via
        // the seed migrator use 730_000 (matches CoreWalletManager.createWallet
        // with isImport: true); other networks start from 0.
        let startHeight: UInt32 = (appNetwork == .mainnet) ? 730_000 : 0
        let sdkNetwork = appNetwork.sdkNetwork

        // Construct the SPVClient.
        let newClient: SPVClient
        do {
            newClient = try SPVClient(
                network: sdkNetwork,
                dataDir: dataDir,
                startHeight: startHeight,
                eventHandlers: handlers)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: SPVClient init failed: \(String(describing: error), privacy: .public)")
            lifecycle = .failed
            applyResetState(lastError: "Failed to create SPV client: \(error.localizedDescription)")
            completion(.failure(StartError.spvClient(error)))
            return
        }

        // Import the runtime wallet bytes into the SPV client's wallet manager.
        do {
            let walletManager = try newClient.getWalletManager()
            let importedWalletId = try walletManager.importWallet(from: walletBytes)
            if importedWalletId != expectedWalletId {
                Self.logger.error("🛰️ SPVCOORD :: imported walletId mismatch")
                lifecycle = .failed
                newClient.destroy()
                applyResetState(lastError: "Imported wallet ID mismatch")
                completion(.failure(StartError.walletIdMismatch))
                return
            }
            Self.logger.info("🛰️ SPVCOORD :: wallet imported into SPV client OK")

            // Seed the initial wallet balance now that the wallet is
            // registered with the FFI. The actual fetch + publish
            // happens in `SwiftDashSDKWalletState.seedInitialBalance` —
            // wallet state lives outside the SPV coordinator's "chain
            // sync" responsibility.
            SwiftDashSDKWalletState.shared.seedInitialBalance(
                walletManager: walletManager,
                walletId: expectedWalletId)

            // Seed the initial transaction list. On cold launch this may
            // be empty (SPV hasn't replayed blocks yet); it fills
            // progressively as blocks are processed. Function #6.
            SwiftDashSDKWalletState.shared.seedTransactions(
                walletManager: walletManager,
                walletId: expectedWalletId)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: failed to import wallet into SPV client: \(String(describing: error), privacy: .public)")
            lifecycle = .failed
            newClient.destroy()
            applyResetState(lastError: "Failed to import wallet: \(error.localizedDescription)")
            completion(.failure(StartError.walletImport(error)))
            return
        }

        client = newClient
        lifecycle = .running
        publish { $0.lastError = nil }
        completion(.success(()))

        // Kick off sync. `SPVClient.startSync()` is async and runs the
        // FFI client until completion or until `stopSync()` is called from
        // another thread. Errors are funneled into `lastError`; the
        // coordinator never throws to its callers.
        Task { [weak self] in
            do {
                try await newClient.startSync()
                Self.logger.info("🛰️ SPVCOORD :: startSync returned — sync loop exited")
            } catch {
                Self.logger.error("🛰️ SPVCOORD :: startSync threw: \(String(describing: error), privacy: .public)")
                guard let self else { return }
                self.workQueue.async {
                    self.lifecycle = .failed
                    self.publish { $0.lastError = "Sync failed: \(error.localizedDescription)" }
                }
            }
        }
    }

    /// Heavy-lifting stop path. Runs on `workQueue`. Calls `stopSync()` on
    /// the active client (which interrupts the `startSync()` task), then
    /// `destroy()` to release the FFI handles and unlock the data dir.
    private func performStop(lastError: String?, completion: (() -> Void)?) {
        if let activeClient = client {
            Self.logger.info("🛰️ SPVCOORD :: stopping SPV client")
            activeClient.stopSync()
            activeClient.destroy()
        } else {
            Self.logger.info("🛰️ SPVCOORD :: stop requested with no active SPV client")
        }
        client = nil
        lifecycle = .stopped
        applyResetState(lastError: lastError)
        completion?()
    }

    /// Compute and create the SPV data directory for a given network.
    /// Returns the absolute filesystem path. Throws on filesystem errors.
    private func ensureDataDirectory(for network: AppNetwork) throws -> String {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        let dataDir = documents
            .appendingPathComponent("SwiftDashSDK", isDirectory: true)
            .appendingPathComponent("SPV", isDirectory: true)
            .appendingPathComponent(network.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dataDir,
            withIntermediateDirectories: true)
        return dataDir.path
    }

    // MARK: - Publish helpers

    /// Apply mutations to `self` from the work queue and trigger
    /// `objectWillChange` on the main queue so SwiftUI / Combine consumers
    /// receive updates on the right thread. Closure runs on the main queue.
    fileprivate func publish(_ mutate: @escaping (SwiftDashSDKSPVCoordinator) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            mutate(self)
        }
    }

    private func applyResetState(lastError: String?) {
        let resetBlock = { [weak self] in
            guard let self else { return }
            self.progress = 0.0
            self.state = .idle
            self.tipHeight = 0
            self.bestPeerHeight = 0
            self.connectedPeerCount = 0
            self.syncProgress = .default()
            self.isComplete = false
            self.lastError = lastError
        }

        if Thread.isMainThread {
            resetBlock()
        } else {
            DispatchQueue.main.sync(execute: resetBlock)
        }
    }

    enum StartError: LocalizedError {
        case dataDirectory(Error)
        case spvClient(Error)
        case walletImport(Error)
        case walletIdMismatch

        var errorDescription: String? {
            switch self {
            case .dataDirectory(let error):
                return "Failed to create SPV data directory: \(error.localizedDescription)"
            case .spvClient(let error):
                return "Failed to create SPV client: \(error.localizedDescription)"
            case .walletImport(let error):
                return "Failed to import wallet: \(error.localizedDescription)"
            case .walletIdMismatch:
                return "Imported wallet ID mismatch"
            }
        }
    }

    // MARK: - Event handler nested classes
    //
    // Each conforms to one of the 5 SPV event handler protocols. They hold
    // a weak reference to the coordinator and forward events to its
    // `publish(_:)` method. We deliberately re-implement these instead of
    // reusing `WalletService.swift`'s 12 active stub bodies — see
    // SWIFT_SDK_SPV_GAPS.md for the gap inventory and rationale.

    private final class ProgressUpdateHandler: SPVProgressUpdateEventHandler {
        weak var coordinator: SwiftDashSDKSPVCoordinator?
        init(coordinator: SwiftDashSDKSPVCoordinator) {
            self.coordinator = coordinator
        }
        func onProgressUpdate(_ progress: SPVSyncProgress) {
            coordinator?.publish {
                $0.syncProgress = progress
                $0.progress = progress.percentage
                $0.state = progress.state
                $0.isComplete = progress.state.isComplete()
            }
        }
    }

    private final class SyncEventsHandler: SPVSyncEventsHandler {
        weak var coordinator: SwiftDashSDKSPVCoordinator?
        init(coordinator: SwiftDashSDKSPVCoordinator) {
            self.coordinator = coordinator
        }
        func onStart(_ manager: SPVSyncManager) {
            SwiftDashSDKSPVCoordinator.logger.debug("🛰️ SPVCOORD :: sync start: \(String(describing: manager), privacy: .public)")
        }
        func onComplete(_ headerTip: UInt32, _ cycle: UInt32) {
            SwiftDashSDKSPVCoordinator.logger.info("🛰️ SPVCOORD :: sync cycle complete: tip=\(headerTip, privacy: .public) cycle=\(cycle, privacy: .public)")
            coordinator?.publish { $0.tipHeight = headerTip }
        }
        func onBlockHeadersStored(_ tipHeight: UInt32) {
            coordinator?.publish { $0.tipHeight = tipHeight }
        }
        func onBlockHeadersSyncCompleted(_ tipHeight: UInt32) {
            coordinator?.publish { $0.tipHeight = tipHeight }
        }
        func onFilterHeadersStored(_ startHeight: UInt32, _ endHeight: UInt32, _ tipHeight: UInt32) {
            coordinator?.publish { $0.tipHeight = tipHeight }
        }
        func onFilterHeadersSyncCompleted(_ tipHeight: UInt32) {
            coordinator?.publish { $0.tipHeight = tipHeight }
        }
        func onFilterStored(_ startHeight: UInt32, _ endHeight: UInt32) {
            // No state mutation — covered by `onFilterSyncCompleted`'s tip.
        }
        func onFilterSyncCompleted(_ tipHeight: UInt32) {
            coordinator?.publish { $0.tipHeight = tipHeight }
        }
        func onBlocksNeeded(_ height: UInt32, _ hash: Data, _ count: UInt32) {
            // Future use: surface "block download in progress" UI granularity.
        }
        func onBlocksProcessed(_ height: UInt32, _ hash: Data, _ newAddressCount: UInt32) {
            // Future use: trigger transaction-list refresh when newAddressCount > 0.
        }
        func onMasternodeStateUpdated(_ height: UInt32) {
            // Future use: when masternode list exposure lands upstream
            // (see SWIFT_SDK_SPV_GAPS.md), surface this for the Tech Info display.
        }
        func onChainLockReceived(_ height: UInt32, _ hash: Data, _ signature: Data, _ validated: Bool) {
            // Future use: M9 hooks transaction confirmation state into this.
        }
        func onInstantLockReceived(_ txid: Data, _ instantLockData: Data, _ validated: Bool) {
            // Future use: M9 hooks Transaction.swift IS state into this.
        }
        func onSyncManagerError(_ manager: SPVSyncManager, _ errorMsg: String) {
            SwiftDashSDKSPVCoordinator.logger.error("🛰️ SPVCOORD :: sync manager error (\(String(describing: manager), privacy: .public)): \(errorMsg, privacy: .public)")
            coordinator?.publish { $0.lastError = errorMsg }
        }
    }

    private final class NetworkEventsHandler: SPVNetworkEventsHandler {
        weak var coordinator: SwiftDashSDKSPVCoordinator?
        init(coordinator: SwiftDashSDKSPVCoordinator) {
            self.coordinator = coordinator
        }
        func onPeerConnected(_ address: String) {
            // Logging only — count comes from `onPeersUpdated`.
        }
        func onPeerDisconnected(_ address: String) {
            // Logging only — count comes from `onPeersUpdated`.
        }
        func onPeersUpdated(_ connectedCount: UInt32, _ bestHeight: UInt32) {
            coordinator?.publish {
                $0.connectedPeerCount = connectedCount
                $0.bestPeerHeight = bestHeight
            }
        }
    }

    private final class WalletEventsHandler: SPVWalletEventsHandler {
        weak var coordinator: SwiftDashSDKSPVCoordinator?
        init(coordinator: SwiftDashSDKSPVCoordinator) {
            self.coordinator = coordinator
        }
        func onTransactionReceived(_ walletId: String, _ accountIndex: UInt32, _ record: NotOwnedTransactionRecord) {
            SwiftDashSDKSPVCoordinator.logger.info("🛰️ SPVCOORD :: tx received: wallet=\(walletId, privacy: .public) account=\(accountIndex, privacy: .public)")
            // Dispatch to a background queue to avoid re-entering the FFI
            // from within the callback. The SPV client holds a lock during
            // callback dispatch; calling getWalletManager() synchronously
            // here would cause a Rust panic (re-entrant lock). Function #6.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let coordinator = self?.coordinator, let client = coordinator.client else { return }
                do {
                    let walletManager = try client.getWalletManager()
                    let walletIdData = Data(hexString: walletId)
                    if let walletIdData {
                        let account = try walletManager.getManagedAccount(
                            walletId: walletIdData, accountIndex: accountIndex, accountType: .standardBIP44)
                        let txs = account.getTransactions()
                        SwiftDashSDKWalletState.shared.applyTransactions(txs)
                    }
                } catch {
                    SwiftDashSDKSPVCoordinator.logger.error("🛰️ SPVCOORD :: tx re-fetch failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        func onBalanceUpdated(_ walletId: String, _ spendable: UInt64, _ unconfirmed: UInt64, _ immature: UInt64, _ locked: UInt64) {
            SwiftDashSDKSPVCoordinator.logger.info("🛰️ SPVCOORD :: balance updated: wallet=\(walletId, privacy: .public) spendable=\(spendable, privacy: .public) unconfirmed=\(unconfirmed, privacy: .public) immature=\(immature, privacy: .public) locked=\(locked, privacy: .public)")
            // The callback's `spendable` is `confirmed - locked` per the
            // SDK's KeyWalletTypes.swift documentation. Add `locked` back
            // to recover `confirmed` for the WalletBalance snapshot.
            // Forward to the wallet state singleton — the SPV coordinator
            // does not own wallet-side @Published state.
            let confirmed = spendable + locked
            let snapshot = WalletBalance(
                confirmed: confirmed,
                unconfirmed: unconfirmed,
                immature: immature,
                locked: locked)
            SwiftDashSDKWalletState.shared.applyBalance(snapshot)
        }
    }

    private final class ErrorEventsHandler: SPVClientErrorEventsHandler {
        weak var coordinator: SwiftDashSDKSPVCoordinator?
        init(coordinator: SwiftDashSDKSPVCoordinator) {
            self.coordinator = coordinator
        }
        func onError(_ errorMsg: String) {
            SwiftDashSDKSPVCoordinator.logger.error("🛰️ SPVCOORD :: client error: \(errorMsg, privacy: .public)")
            coordinator?.publish { $0.lastError = errorMsg }
        }
    }
}
