//
//  SwiftDashSDKSPVCoordinator.swift
//  DashWallet
//
//  ⚠️ Core SPV is currently DISABLED.
//
//  The SwiftDashSDK refactor `ab6dfbf7b refactor(swift-sdk): route
//  everything through PlatformWalletManager` deleted the entire
//  standalone core-SPV surface this coordinator was built on
//  (`SPVClient`, `SPVSyncState`, `SPVSyncProgress`, `SPVEventHandlers`,
//  and all five `SPV*EventsHandler` protocols). Rather than delete this
//  coordinator outright (which would cascade into `SyncingActivityMonitor`,
//  `SwiftDashSDKSPVStatusScreen`, `SwiftDashSDKWalletRuntime`,
//  `SwiftDashSDKTransactionSender`, and several UI surfaces), we keep the
//  same public shape but stub every method.
//
//  Behaviour while disabled:
//  - `@Published` properties keep their default values forever.
//  - `start(with:completion:)` fails with `StartError.coreSPVDisabled`.
//  - `stop(lastError:completion:)` is a no-op (state is already default).
//  - `isRunning(for:)` always returns `false`.
//  - `getWalletManager()` and `broadcastTransaction(_:)` throw
//    `TransactionSenderError.spvNotRunning`, so callers surface a
//    clean error instead of crashing.
//
//  The live SPV path has moved to `PlatformSDKCoordinator`, which wraps
//  `PlatformWalletManager`. The Tools → "Platform SPV Status" screen
//  observes it. When the core-SPV surface is reinstated (either by
//  reviving the old SDK types or by migrating this coordinator onto
//  `PlatformWalletManager`), this file goes back to being the
//  authoritative chain-sync owner.
//
//  Local type stand-ins are defined at file scope below so the
//  consumers (`SyncingActivityMonitor`, `SwiftDashSDKSPVStatusScreen`)
//  resolve the same names they used against the old SDK.
//

import Combine
import Foundation
import OSLog
import SwiftDashSDK

// MARK: - Local stand-ins for removed SDK types

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

// MARK: - SwiftDashSDKSPVCoordinator (neutered)

@objc(DWSwiftDashSDKSPVCoordinator)
public final class SwiftDashSDKSPVCoordinator: NSObject, ObservableObject {

    // MARK: - Singleton

    public static let shared = SwiftDashSDKSPVCoordinator()

    // MARK: - Logging

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.spv-coordinator")

    // MARK: - Published state (never mutated while core SPV is disabled)

    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var state: SPVSyncState = .idle
    @Published public private(set) var tipHeight: UInt32 = 0
    @Published public private(set) var bestPeerHeight: UInt32 = 0
    @Published public private(set) var connectedPeerCount: UInt32 = 0
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var isComplete: Bool = false
    @Published public private(set) var syncProgress: SPVSyncProgress = .default()

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Public lifecycle

    func start(with wallet: HDWallet, completion: @escaping (Result<Void, Error>) -> Void) {
        Self.logger.warning("🛰️ SPVCOORD :: core SPV disabled — start ignored (see PlatformSDKCoordinator for the live sync path)")
        completion(.failure(StartError.coreSPVDisabled))
    }

    func stop(lastError: String?, completion: (() -> Void)? = nil) {
        Self.logger.info("🛰️ SPVCOORD :: core SPV disabled — stop is a no-op")
        if let lastError {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = lastError
            }
        }
        completion?()
    }

    func isRunning(for network: AppNetwork) -> Bool {
        false
    }

    @objc(stop)
    public static func stop() {
        shared.stop(lastError: nil, completion: nil)
    }

    // MARK: - Transaction support (throw while disabled)

    func getWalletManager() throws -> WalletManager {
        throw TransactionSenderError.spvNotRunning
    }

    func broadcastTransaction(_ data: Data) throws {
        throw TransactionSenderError.spvNotRunning
    }

    // MARK: - Errors

    enum TransactionSenderError: LocalizedError {
        case spvNotRunning

        var errorDescription: String? {
            switch self {
            case .spvNotRunning:
                return "Wallet not ready — core SPV client is disabled"
            }
        }
    }

    enum StartError: LocalizedError {
        case coreSPVDisabled
        case dataDirectory(Error)
        case spvClient(Error)
        case walletImport(Error)
        case walletIdMismatch

        var errorDescription: String? {
            switch self {
            case .coreSPVDisabled:
                return "Core SPV is temporarily disabled pending SDK migration"
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
}
