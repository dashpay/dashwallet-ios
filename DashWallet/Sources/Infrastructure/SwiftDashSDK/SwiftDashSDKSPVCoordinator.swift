//
//  SwiftDashSDKSPVCoordinator.swift
//  DashWallet
//
//  Drives Core SPV (headers / filter headers / filters / masternodes) via
//  `PlatformWalletManager.startSpv/stopSpv/clearSpvStorage`. Mirrors the
//  pattern used in the SwiftDashSDK sample app's `CoreContentView`.
//
//  The coordinator is a thin facade over `SwiftDashSDKHost.shared`, which
//  owns the singleton `PlatformWalletManager` instance shared with the
//  Platform L2 BLAST sync (`PlatformAddressSyncCoordinator`). Two
//  managers would mean two FFI handles and divergent SwiftData
//  persistence, so all sync subsystems consume the host's single instance.
//
//  Public surface (Combine `@Published` + Obj-C `@objc(stop)`) is preserved
//  so existing consumers (`SyncingActivityMonitor`,
//  `SwiftDashSDKSPVStatusScreen`, `SwiftDashSDKWalletRuntime`,
//  `SwiftDashSDKTransactionSender`) keep working without rewires.
//
//  The local stand-in types (`SPVSyncState`, `SPVSyncProgress`,
//  `PhaseSubProgress`, etc. below) survived the SDK refactor and are now
//  used as the published shape; we translate from the SDK's
//  `PlatformSpvSyncProgress` into them on every poll tick.
//

import Combine
import Foundation
import OSLog
import SwiftDashSDK

// MARK: - Local stand-ins for SDK surface that consumers still expect

/// Local replacement for the SDK's removed `SPVSyncState`. Shape matches
/// what consumers read.
public enum SPVSyncState {
    case idle
    case waitForEvents
    case waitingForConnections
    case syncing
    case synced
    case error
    case unknown

    public func isComplete() -> Bool { self == .synced }
}

/// Local replacement for the SDK's removed `SPVSyncProgress`.
public struct SPVSyncProgress {
    public var state: SPVSyncState
    public var percentage: Double
    public var headers: PhaseSubProgress?
    public var filterHeaders: PhaseSubProgress?
    public var filters: PhaseSubProgress?
    public var blocks: BlocksSubProgress?
    public var masternodes: MasternodesSubProgress?
    public var chainLocks: ChainLocksSubProgress?
    public var instantSend: InstantSendSubProgress?

    public static func `default`() -> SPVSyncProgress {
        SPVSyncProgress(
            state: .idle,
            percentage: 0.0,
            headers: nil,
            filterHeaders: nil,
            filters: nil,
            blocks: nil,
            masternodes: nil,
            chainLocks: nil,
            instantSend: nil)
    }
}

public struct PhaseSubProgress {
    public let state: SPVSyncState
    public let percentage: Double
    public let currentHeight: UInt32
    public let targetHeight: UInt32
}

public struct BlocksSubProgress {
    public let state: SPVSyncState
    public let lastProcessed: UInt32
}

public struct MasternodesSubProgress {
    public let state: SPVSyncState
    public let currentHeight: UInt32
    public let targetHeight: UInt32
    public let diffsProcessed: UInt32
}

public struct ChainLocksSubProgress {
    public let state: SPVSyncState
    public let bestValidatedHeight: UInt32
}

public struct InstantSendSubProgress {
    public let state: SPVSyncState
    public let valid: UInt32
}

// MARK: - SwiftDashSDKSPVCoordinator

@objc(DWSwiftDashSDKSPVCoordinator)
public final class SwiftDashSDKSPVCoordinator: NSObject, ObservableObject {

    // MARK: - Singleton

    public static let shared = SwiftDashSDKSPVCoordinator()

    // MARK: - Logging

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.spv-coordinator")

    // MARK: - Published state

    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var state: SPVSyncState = .idle
    @Published public private(set) var tipHeight: UInt32 = 0
    @Published public private(set) var bestPeerHeight: UInt32 = 0
    @Published public private(set) var connectedPeerCount: UInt32 = 0
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var isComplete: Bool = false
    @Published public private(set) var syncProgress: SPVSyncProgress = .default()

    // MARK: - Internal state

    private var runningNetwork: AppNetwork?
    private var progressCancellable: AnyCancellable?

    /// Mirror of running state, readable without hopping to the main actor.
    /// `WalletRuntime.shouldSkipRefresh` reads `isRunning(for:)` from a
    /// non-main `DispatchQueue`, so the lock — not the actor — is the
    /// concurrency boundary.
    private struct CachedRunState {
        var network: AppNetwork?
        var running: Bool
    }
    private let cacheLock = NSLock()
    private var cachedRunState = CachedRunState(network: nil, running: false)

    private func updateCachedRunState(network: AppNetwork?, running: Bool) {
        cacheLock.lock()
        cachedRunState = CachedRunState(network: network, running: running)
        cacheLock.unlock()
    }

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Public lifecycle (called via DispatchGroup from workQueue)

    func start(with wallet: HDWallet, completion: @escaping (Result<Void, Error>) -> Void) {
        Task { @MainActor in
            let result = self.performStart(with: wallet)
            completion(result)
        }
    }

    func stop(lastError: String?, completion: (() -> Void)? = nil) {
        Task { @MainActor in
            self.performStop(lastError: lastError)
            completion?()
        }
    }

    func isRunning(for network: AppNetwork) -> Bool {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedRunState.running && cachedRunState.network == network
    }

    @objc(stop)
    public static func stop() {
        shared.stop(lastError: nil, completion: nil)
    }

    // MARK: - Transaction support

    /// Broadcast a previously-signed Core transaction via the live SPV
    /// network. Throws if the host is not started or the wallet is not yet
    /// available.
    ///
    /// The actual SDK call must run on the main actor (the wallet handle
    /// is `@MainActor`-isolated); we trampoline through
    /// `DispatchQueue.main.sync` if invoked from a background thread.
    /// Synchronous to keep `@objc(broadcastAndReturnError:)` Obj-C call
    /// sites working without async-conversion.
    func broadcastTransaction(_ data: Data) throws {
        if Thread.isMainThread {
            try MainActor.assumeIsolated {
                try _broadcastOnMain(data)
            }
        } else {
            var thrownError: Error?
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    do {
                        try _broadcastOnMain(data)
                    } catch {
                        thrownError = error
                    }
                }
            }
            if let thrownError {
                throw thrownError
            }
        }
    }

    @MainActor
    private func _broadcastOnMain(_ data: Data) throws {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            throw TransactionSenderError.spvNotRunning
        }
        let core = try wallet.coreWallet()
        _ = try core.broadcastTransaction(data)
    }

    /// Stubbed — `SwiftDashSDKTransactionSender.buildAndSign` is currently
    /// disabled (the SDK now bundles build+sign+broadcast into a single
    /// `coreWallet().sendToAddresses(...)` call which doesn't fit the
    /// existing PIN-gated build/broadcast split). Reinstate when that send
    /// path is reworked.
    func getWalletManager() throws -> WalletManager {
        throw TransactionSenderError.spvNotRunning
    }

    // MARK: - Implementation

    @MainActor
    private func performStart(with wallet: HDWallet) -> Result<Void, Error> {
        let network = wallet.network

        let host = SwiftDashSDKHost.shared
        let manager: PlatformWalletManager
        do {
            (manager, _) = try host.start(network: network)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: host.start failed: \(String(describing: error), privacy: .public)")
            return .failure(StartError.walletImport(error))
        }

        // If SPV is already running on this network, treat it as a
        // success. Mirrors `SwiftDashSDKWalletRuntime.shouldSkipRefresh`'s
        // start-elision intent.
        if (try? manager.isSpvRunning()) == true, runningNetwork == network {
            Self.logger.info("🛰️ SPVCOORD :: already running on \(network.rawValue, privacy: .public)")
            return .success(())
        }

        guard let platformNet = host.platformNetwork(for: network) else {
            return .failure(StartError.dataDirectory(HostUnsupportedNetwork(network: network)))
        }

        let dataDir: String
        do {
            dataDir = try makeSPVDataDirectory(for: network).path
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: SPV dataDir failed: \(String(describing: error), privacy: .public)")
            return .failure(StartError.dataDirectory(error))
        }

        let config = PlatformSpvStartConfig(
            dataDir: dataDir,
            network: platformNet,
            userAgent: nil,
            peers: [],
            restrictToConfiguredPeers: false,
            startFromHeight: 0,
            masternodeSyncEnabled: true)

        do {
            try manager.startSpv(config: config)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: startSpv failed: \(String(describing: error), privacy: .public)")
            return .failure(StartError.spvClient(error))
        }

        runningNetwork = network
        updateCachedRunState(network: network, running: true)
        lastError = nil
        subscribeToManagerProgress(manager: manager)

        Self.logger.info("🛰️ SPVCOORD :: started on \(network.rawValue, privacy: .public)")
        return .success(())
    }

    @MainActor
    private func performStop(lastError: String?) {
        progressCancellable?.cancel()
        progressCancellable = nil

        if let manager = SwiftDashSDKHost.shared.manager {
            do {
                if try manager.isSpvRunning() {
                    try manager.stopSpv()
                }
                Self.logger.info("🛰️ SPVCOORD :: stopped")
            } catch {
                Self.logger.error("🛰️ SPVCOORD :: stopSpv threw: \(String(describing: error), privacy: .public)")
            }
        }

        runningNetwork = nil
        updateCachedRunState(network: nil, running: false)
        resetPublishedState()
        if let lastError {
            self.lastError = lastError
        }
    }

    @MainActor
    private func subscribeToManagerProgress(manager: PlatformWalletManager) {
        progressCancellable = manager.$spvProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] platformProgress in
                self?.applyProgress(platformProgress)
            }
    }

    private func applyProgress(_ p: PlatformSpvSyncProgress) {
        let mappedState = mapState(p.overallState)
        let translated = SPVSyncProgress(
            state: mappedState,
            percentage: p.overallPercentage,
            headers: p.headers.map(mapPhase),
            filterHeaders: p.filterHeaders.map(mapPhase),
            filters: p.filters.map(mapPhase),
            blocks: nil,
            masternodes: p.masternodes.map { sub in
                MasternodesSubProgress(
                    state: mapState(sub.state),
                    currentHeight: sub.currentHeight,
                    targetHeight: sub.targetHeight,
                    diffsProcessed: 0)
            },
            chainLocks: nil,
            instantSend: nil)

        // Best-effort tip / peer-height: the new SDK doesn't expose peer
        // counts or a discrete "best peer" height. Approximate from the
        // headers phase — current = our tip, target = best known.
        let headersCurrent = p.headers?.currentHeight ?? 0
        let headersTarget = p.headers?.targetHeight ?? 0

        // Assign all derived properties together so downstream
        // `combineLatest` consumers (`SyncingActivityMonitor`) see a
        // coherent snapshot.
        syncProgress = translated
        progress = p.overallPercentage
        state = mappedState
        tipHeight = headersCurrent
        bestPeerHeight = max(headersTarget, headersCurrent)
        isComplete = mappedState.isComplete()
        if mappedState != .error {
            lastError = nil
        }
    }

    private func resetPublishedState() {
        progress = 0.0
        state = .idle
        tipHeight = 0
        bestPeerHeight = 0
        connectedPeerCount = 0
        isComplete = false
        syncProgress = .default()
    }

    // MARK: - Mapping

    private func mapState(_ state: PlatformSpvSyncState) -> SPVSyncState {
        switch state {
        case .waitForEvents: return .waitForEvents
        case .waitingForConnections: return .waitingForConnections
        case .syncing: return .syncing
        case .synced: return .synced
        case .error: return .error
        }
    }

    private func mapPhase(_ sub: PlatformSpvSubProgress) -> PhaseSubProgress {
        PhaseSubProgress(
            state: mapState(sub.state),
            percentage: sub.percentage,
            currentHeight: sub.currentHeight,
            targetHeight: sub.targetHeight)
    }

    // MARK: - Filesystem

    private func makeSPVDataDirectory(for network: AppNetwork) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        let dir = documents
            .appendingPathComponent("SPV", isDirectory: true)
            .appendingPathComponent(network.networkName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Errors

    enum TransactionSenderError: LocalizedError {
        case spvNotRunning

        var errorDescription: String? {
            switch self {
            case .spvNotRunning:
                return "Wallet not ready — Core SPV is not running"
            }
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
                return "Failed to start SPV client: \(error.localizedDescription)"
            case .walletImport(let error):
                return "Failed to import wallet: \(error.localizedDescription)"
            case .walletIdMismatch:
                return "Imported wallet ID mismatch"
            }
        }
    }

    private struct HostUnsupportedNetwork: LocalizedError {
        let network: AppNetwork
        var errorDescription: String? { "Platform SDK does not support \(network.rawValue)" }
    }
}
