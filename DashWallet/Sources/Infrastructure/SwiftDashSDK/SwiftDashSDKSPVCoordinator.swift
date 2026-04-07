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
//    3. NEVER starts before the seed migrator's `swiftSDKKeyMigration.v1.done`
//       flag is set. The coordinator polls the flag with a backoff loop and
//       bails out (logging) if the migrator never completes.
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
//  Milestone 2 of the SPV chain sync migration. The coordinator is fully
//  implemented as far as the lifecycle goes, but is NOT yet started from
//  `AppDelegate.m` — that's milestone 4. Until M4 lands, this file compiles
//  and is dead.
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@objc(DWSwiftDashSDKSPVCoordinator)
public final class SwiftDashSDKSPVCoordinator: NSObject, ObservableObject {

    // MARK: - Singleton

    /// Shared instance. Swift consumers access published state via this
    /// reference; Obj-C consumers go through the @objc class methods below
    /// (`startIfReady`, `stop`).
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
        case waitingForSeedMigrator
        case starting
        case running
        case stopped
        case failed
    }
    private var lifecycle: LifecycleState = .notStarted

    /// UserDefaults key written by `SwiftDashSDKKeyMigrator` when the seed
    /// migration is complete. The coordinator polls this before constructing
    /// an `SPVClient`.
    private static let seedMigratorDoneKey = "swiftSDKKeyMigration.v1.done"

    /// Maximum time to wait for the seed migrator to complete before giving
    /// up and marking the coordinator as `failed`.
    private static let seedMigratorWaitTimeout: TimeInterval = 30.0

    /// Polling interval while waiting for the seed migrator's done flag.
    private static let seedMigratorPollInterval: TimeInterval = 0.1

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Public lifecycle (Obj-C accessible)

    /// Idempotent entry point. Schedules SPV start on the background queue
    /// and returns immediately. If already running, no-op.
    ///
    /// If the seed migrator has not yet written its `swiftSDKKeyMigration.v1.done`
    /// flag, the coordinator polls the flag for up to `seedMigratorWaitTimeout`
    /// seconds before bailing out and marking itself `failed`.
    ///
    /// Never throws, never crashes.
    @objc(startIfReady)
    public static func startIfReady() {
        let coordinator = shared
        coordinator.workQueue.async {
            coordinator.performStart()
        }
    }

    /// Stops the SPV client and destroys it. The coordinator can be restarted
    /// later via `startIfReady()`, which constructs a fresh `SPVClient`
    /// because of the FFI's "no resume after stop" limitation
    /// (see `SPVClient.swift:12-16`).
    @objc(stop)
    public static func stop() {
        let coordinator = shared
        coordinator.workQueue.async {
            coordinator.performStop()
        }
    }

    // MARK: - Background lifecycle

    /// Heavy-lifting start path. Runs on `workQueue`. Polls the seed migrator,
    /// reads the migrated `HDWallet` from SwiftData, constructs an `SPVClient`
    /// with our event handlers, imports the wallet bytes into the client's
    /// wallet manager, and kicks off `startSync()`.
    private func performStart() {
        // Idempotent guard.
        switch lifecycle {
        case .starting, .running:
            Self.logger.info("startIfReady ignored — coordinator is already \(String(describing: self.lifecycle), privacy: .public)")
            return
        case .waitingForSeedMigrator, .notStarted, .stopped, .failed:
            break
        }

        lifecycle = .waitingForSeedMigrator
        Self.logger.info("waiting for seed migrator (`\(Self.seedMigratorDoneKey, privacy: .public)`)")

        // Poll the migrator's done flag with a bounded backoff.
        let deadline = Date().addingTimeInterval(Self.seedMigratorWaitTimeout)
        while UserDefaults.standard.string(forKey: Self.seedMigratorDoneKey) == nil {
            if Date() >= deadline {
                Self.logger.error("seed migrator did not complete within \(Self.seedMigratorWaitTimeout, privacy: .public)s — bailing")
                lifecycle = .failed
                publish { $0.lastError = "Seed migration not complete; SPV cannot start." }
                return
            }
            Thread.sleep(forTimeInterval: Self.seedMigratorPollInterval)
        }

        // Read the migrated HDWallet record from SwiftData.
        let migratedWallet: HDWallet
        do {
            let modelContainer = try ModelContainerHelper.createContainer()
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<HDWallet>()
            let wallets = try context.fetch(descriptor)
            guard let first = wallets.first else {
                Self.logger.warning("seed migrator marked done but no HDWallet found — fresh install path, nothing to sync")
                lifecycle = .stopped
                return
            }
            migratedWallet = first
        } catch {
            Self.logger.error("failed to read migrated HDWallet: \(String(describing: error), privacy: .public)")
            lifecycle = .failed
            publish { $0.lastError = "Failed to read migrated wallet: \(error.localizedDescription)" }
            return
        }

        let appNetwork = migratedWallet.network
        let walletBytes = migratedWallet.serializedWalletBytes
        let expectedWalletId = migratedWallet.walletId

        Self.logger.info("starting SPV client for \(String(describing: appNetwork), privacy: .public), wallet bytes=\(walletBytes.count, privacy: .public)")

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
            Self.logger.error("failed to create SPV data directory: \(String(describing: error), privacy: .public)")
            lifecycle = .failed
            publish { $0.lastError = "Failed to create SPV data directory: \(error.localizedDescription)" }
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
            Self.logger.error("SPVClient init failed: \(String(describing: error), privacy: .public)")
            lifecycle = .failed
            publish { $0.lastError = "Failed to create SPV client: \(error.localizedDescription)" }
            return
        }

        // Import the migrated wallet into the SPV client's wallet manager.
        do {
            let walletManager = try newClient.getWalletManager()
            let importedWalletId = try walletManager.importWallet(from: walletBytes)
            if importedWalletId != expectedWalletId {
                Self.logger.warning("imported walletId mismatch — proceeding anyway")
            } else {
                Self.logger.info("wallet imported into SPV client OK")
            }
        } catch {
            Self.logger.error("failed to import wallet into SPV client: \(String(describing: error), privacy: .public)")
            lifecycle = .failed
            publish { $0.lastError = "Failed to import wallet: \(error.localizedDescription)" }
            newClient.destroy()
            return
        }

        client = newClient
        lifecycle = .running
        publish { $0.lastError = nil }

        // Kick off sync. `SPVClient.startSync()` is async and runs the
        // FFI client until completion or until `stopSync()` is called from
        // another thread. Errors are funneled into `lastError`; the
        // coordinator never throws to its callers.
        Task { [weak self] in
            do {
                try await newClient.startSync()
                Self.logger.info("startSync returned — sync loop exited")
            } catch {
                Self.logger.error("startSync threw: \(String(describing: error), privacy: .public)")
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
    private func performStop() {
        guard let activeClient = client else {
            Self.logger.info("stop ignored — no active SPV client")
            return
        }
        Self.logger.info("stopping SPV client")
        activeClient.stopSync()
        activeClient.destroy()
        client = nil
        lifecycle = .stopped
        publish {
            $0.state = .idle
            $0.isComplete = false
        }
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
            SwiftDashSDKSPVCoordinator.logger.debug("sync start: \(String(describing: manager), privacy: .public)")
        }
        func onComplete(_ headerTip: UInt32, _ cycle: UInt32) {
            SwiftDashSDKSPVCoordinator.logger.info("sync cycle complete: tip=\(headerTip, privacy: .public) cycle=\(cycle, privacy: .public)")
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
            SwiftDashSDKSPVCoordinator.logger.error("sync manager error (\(String(describing: manager), privacy: .public)): \(errorMsg, privacy: .public)")
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
        func onTransactionReceived(_ walletId: String, _ accountIndex: UInt32, _ txid: Data, _ amount: Int64, _ addresses: [String]) {
            // Future use: feed into the transaction-list refresh path (M9 + function #6 migration).
            SwiftDashSDKSPVCoordinator.logger.info("tx received: wallet=\(walletId, privacy: .public) amount=\(amount, privacy: .public)")
        }
        func onBalanceUpdated(_ walletId: String, _ spendable: UInt64, _ unconfirmed: UInt64, _ immature: UInt64, _ locked: UInt64) {
            // Future use: feed into the balance refresh path (function #5 migration).
            SwiftDashSDKSPVCoordinator.logger.info("balance updated: wallet=\(walletId, privacy: .public) spendable=\(spendable, privacy: .public)")
        }
    }

    private final class ErrorEventsHandler: SPVClientErrorEventsHandler {
        weak var coordinator: SwiftDashSDKSPVCoordinator?
        init(coordinator: SwiftDashSDKSPVCoordinator) {
            self.coordinator = coordinator
        }
        func onError(_ errorMsg: String) {
            SwiftDashSDKSPVCoordinator.logger.error("client error: \(errorMsg, privacy: .public)")
            coordinator?.publish { $0.lastError = errorMsg }
        }
    }
}
