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
//  Public surface is the Combine `@Published` state consumed by
//  `SyncingActivityMonitor` and `SwiftDashSDKSPVStatusScreen` plus the
//  `startAsync(for:)` / `stopAsync(lastError:)` lifecycle driven by
//  `SwiftDashSDKWalletRuntime`'s serial async pipeline.
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
    public var masternodes: MasternodesSubProgress?

    public static func `default`() -> SPVSyncProgress {
        SPVSyncProgress(
            state: .idle,
            percentage: 0.0,
            headers: nil,
            filterHeaders: nil,
            filters: nil,
            masternodes: nil)
    }
}

public struct PhaseSubProgress {
    public let state: SPVSyncState
    public let percentage: Double
    public let currentHeight: UInt32
    public let targetHeight: UInt32
}

public struct MasternodesSubProgress {
    public let state: SPVSyncState
    public let currentHeight: UInt32
    public let targetHeight: UInt32
    public let diffsProcessed: UInt32
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
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var syncProgress: SPVSyncProgress = .default()

    // MARK: - Internal state

    private var runningNetwork: Network?
    private var progressCancellable: AnyCancellable?

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Public lifecycle (async)
    //
    // Invoked by `SwiftDashSDKWalletRuntime`'s single async pipeline,
    // which owns the canonical `currentNetwork` state and serializes
    // start / stop ordering.

    @MainActor
    func startAsync(for network: Network) async throws {
        switch performStart(for: network) {
        case .success: return
        case .failure(let error): throw error
        }
    }

    @MainActor
    func stopAsync(lastError: String?) async {
        performStop(lastError: lastError)
    }

    // MARK: - Implementation

    @MainActor
    private func performStart(for network: Network) -> Result<Void, Error> {
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

        guard network != .regtest else {
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
            network: network,
            userAgent: nil,
            peers: [],
            restrictToConfiguredPeers: false,
            startFromHeight: 0)

        do {
            try manager.startSpv(config: config)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: startSpv failed: \(String(describing: error), privacy: .public)")
            return .failure(StartError.spvClient(error))
        }

        runningNetwork = network
        lastError = nil
        subscribeToManagerProgress(manager: manager)
        refreshBalanceBridge()

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

        // Drop the bridge'd balance so a network switch / wipe doesn't leak
        // the previous wallet's value into the next session. The next
        // `performStart` re-seeds via `refreshBalanceBridge()`.
        SwiftDashSDKWalletState.shared.clearBalance()

        runningNetwork = nil
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
                // `.receive(on: RunLoop.main)` puts us on the main thread,
                // so we can hop into MainActor isolation synchronously to
                // touch the host's `@MainActor` wallet inside applyProgress.
                MainActor.assumeIsolated {
                    self?.applyProgress(platformProgress)
                }
            }
    }

    @MainActor
    private func applyProgress(_ p: PlatformSpvSyncProgress) {
        let mappedState = mapState(p.overallState)
        let translated = SPVSyncProgress(
            state: mappedState,
            percentage: p.overallPercentage,
            headers: p.headers.map(mapPhase),
            filterHeaders: p.filterHeaders.map(mapPhase),
            filters: p.filters.map(mapPhase),
            masternodes: p.masternodes.map { sub in
                MasternodesSubProgress(
                    state: mapState(sub.state),
                    currentHeight: sub.currentHeight,
                    targetHeight: sub.targetHeight,
                    diffsProcessed: 0)
            })

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
        if mappedState != .error {
            lastError = nil
        }

        // Piggyback on the deduped 1Hz progress tick to refresh the live
        // balance into `SwiftDashSDKWalletState.shared` for downstream
        // consumers (BalanceModel, SendAmountModel, etc.).
        refreshBalanceBridge()
    }

    /// Pull the latest core-wallet balance via FFI and republish through
    /// `SwiftDashSDKWalletState.shared.applyBalance(_:)` so the home screen
    /// `BalanceModel` and friends keep working off the same `@Published`
    /// surface they always did. The legacy callback that used to feed this
    /// publisher was removed in the SDK refactor, so the bridge replaces it.
    @MainActor
    private func refreshBalanceBridge() {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            SwiftDashSDKWalletState.shared.clearBalance()
            return
        }
        do {
            let core = try wallet.coreWallet().balance()
            let mapped = WalletBalance(
                confirmed: core.confirmed,
                unconfirmed: core.unconfirmed,
                immature: core.immature,
                locked: core.locked)
            SwiftDashSDKWalletState.shared.applyBalance(mapped)
        } catch {
            Self.logger.warning(
                "🛰️ SPVCOORD :: balance bridge fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func resetPublishedState() {
        progress = 0.0
        state = .idle
        tipHeight = 0
        bestPeerHeight = 0
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

    private func makeSPVDataDirectory(for network: Network) throws -> URL {
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
        let network: Network
        var errorDescription: String? { "Platform SDK does not support \(network.rawValue)" }
    }
}
