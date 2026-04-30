//
//  SwiftDashSDKHost.swift
//  DashWallet
//
//  Singleton owner of the per-network SwiftDashSDK runtime: SDK instance,
//  ModelContainer, PlatformWalletManager handle, and ManagedPlatformWallet.
//
//  The platform repo refactor consolidated Core SPV and Platform L2 BLAST
//  sync onto the same `PlatformWalletManager`. dashwallet-ios needs ONE
//  shared manager across both subsystems — two managers would mean two FFI
//  handles and divergent SwiftData persistence flows. This host owns that
//  shared instance; `SwiftDashSDKSPVCoordinator` (Core SPV) and
//  `PlatformAddressSyncCoordinator` (BLAST) are thin facades on top.
//
//  Lifecycle:
//   - `start(network:)` is idempotent. Re-entering with the same network is
//     a no-op (preserves running SPV / BLAST state). A different network
//     tears down and rebuilds.
//   - `stop(forWipe:)` releases the manager handle. When `forWipe: true`,
//     also deletes the persisted `PersistentWallet` row (so
//     `loadFromPersistor()` returns empty next launch) and the
//     network-scoped `PersistentPlatformAddressesSyncState` row (so BLAST
//     restarts from a fresh checkpoint instead of resuming on stale state).
//
//  Subsystems coordinate ordering through `SwiftDashSDKWalletRuntime`:
//  start = host.start → SPV.start → BLAST.start. Stop = BLAST.stop →
//  SPV.stop → host.stop.
//

import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@MainActor
final class SwiftDashSDKHost {

    // MARK: - Singleton

    static let shared = SwiftDashSDKHost()

    // MARK: - Logging

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.host")

    // MARK: - Owned state

    private(set) var sdk: SDK?
    private(set) var manager: PlatformWalletManager?
    private(set) var wallet: ManagedPlatformWallet?
    private(set) var modelContainer: ModelContainer?
    private(set) var runningNetwork: AppNetwork?

    // MARK: - Process-wide SDK init guard

    private static var sdkInitialized = false
    private static let sdkInitLock = NSLock()

    static func ensureSDKInitialized() {
        sdkInitLock.lock()
        defer { sdkInitLock.unlock() }
        if !sdkInitialized {
            SDK.initialize()
            sdkInitialized = true
        }
    }

    private init() {}

    // MARK: - Lifecycle

    enum HostError: LocalizedError {
        case unsupportedNetwork(AppNetwork)
        case sdkInitFailed(Error)
        case modelContainerFailed(Error)
        case configureFailed(Error)
        case walletBootstrapFailed(Error)

        var errorDescription: String? {
            switch self {
            case .unsupportedNetwork(let network):
                return "Platform SDK does not support \(network.rawValue)"
            case .sdkInitFailed(let error):
                return "SDK init failed: \(error.localizedDescription)"
            case .modelContainerFailed(let error):
                return "ModelContainer setup failed: \(error.localizedDescription)"
            case .configureFailed(let error):
                return "PlatformWalletManager configure failed: \(error.localizedDescription)"
            case .walletBootstrapFailed(let error):
                return "Wallet bootstrap failed: \(error.localizedDescription)"
            }
        }
    }

    /// Start the host for `network`. Idempotent: re-entering with the same
    /// network leaves the live manager + wallet alone. Different network
    /// triggers a clean rebuild via `stop()` first.
    @discardableResult
    func start(network: AppNetwork) throws -> (manager: PlatformWalletManager, wallet: ManagedPlatformWallet) {
        if let existingManager = manager,
           let existingWallet = wallet,
           runningNetwork == network {
            return (existingManager, existingWallet)
        }

        if manager != nil {
            stop()
        }

        guard let platformNetwork = platformNetwork(for: network) else {
            throw HostError.unsupportedNetwork(network)
        }

        Self.ensureSDKInitialized()
        Self.logger.info("🪺 HOST :: starting for \(network.rawValue, privacy: .public)")

        let newSDK: SDK
        do {
            newSDK = try SDK(network: network.sdkNetwork)
        } catch {
            Self.logger.error("🪺 HOST :: SDK init failed: \(String(describing: error), privacy: .public)")
            throw HostError.sdkInitFailed(error)
        }

        let container: ModelContainer
        do {
            container = try buildModelContainer(for: network)
        } catch {
            Self.logger.error("🪺 HOST :: ModelContainer build failed: \(String(describing: error), privacy: .public)")
            throw HostError.modelContainerFailed(error)
        }

        let newManager = PlatformWalletManager()
        do {
            try newManager.configure(sdk: newSDK, modelContainer: container)
        } catch {
            Self.logger.error("🪺 HOST :: configure failed: \(String(describing: error), privacy: .public)")
            throw HostError.configureFailed(error)
        }

        let resolvedWallet: ManagedPlatformWallet
        do {
            resolvedWallet = try bootstrapWallet(manager: newManager, network: platformNetwork)
        } catch {
            Self.logger.error("🪺 HOST :: wallet bootstrap failed: \(String(describing: error), privacy: .public)")
            throw HostError.walletBootstrapFailed(error)
        }

        sdk = newSDK
        manager = newManager
        wallet = resolvedWallet
        modelContainer = container
        runningNetwork = network

        Self.logger.info("🪺 HOST :: started for \(network.rawValue, privacy: .public)")
        return (newManager, resolvedWallet)
    }

    /// Tear down the host's references. The actual SDK / FFI handles drop
    /// when their last strong reference goes away.
    ///
    /// Persisted-row cleanup on wipe is owned by `PlatformAddressSyncCoordinator`
    /// — it must happen BEFORE BLAST's tokio task winds down so in-flight
    /// `walletNetwork(walletId:)` callbacks early-exit on an empty fetch.
    /// The host is torn down last (after BLAST + SPV stops), so the
    /// invariant doesn't hold here.
    func stop() {
        manager = nil
        wallet = nil
        sdk = nil
        modelContainer = nil
        runningNetwork = nil

        Self.logger.info("🪺 HOST :: stopped")
    }

    // MARK: - Wallet bootstrap

    private func bootstrapWallet(
        manager: PlatformWalletManager,
        network: PlatformNetwork
    ) throws -> ManagedPlatformWallet {
        let restored = try manager.loadFromPersistor()
        if let first = restored.first {
            Self.logger.info("🪺 HOST :: reusing persisted wallet")
            return first
        }
        if let existing = manager.firstWallet {
            return existing
        }

        let storage = WalletStorage()
        let walletIds = try storage.listWalletIdsWithMnemonic()
        guard let walletId = walletIds.first else {
            throw WalletStorageError.mnemonicNotFound
        }
        let mnemonic = try storage.retrieveMnemonic(for: walletId)
        Self.logger.info("🪺 HOST :: creating new platform wallet from existing mnemonic")
        return try manager.createWallet(
            mnemonic: mnemonic,
            network: network,
            name: "dashwallet",
            createDefaultAccounts: true)
    }

    // MARK: - Network helpers

    func platformNetwork(for network: AppNetwork) -> PlatformNetwork? {
        switch network {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        case .regtest: return nil
        }
    }

    // MARK: - ModelContainer

    private func buildModelContainer(for network: AppNetwork) throws -> ModelContainer {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        let dir = documents
            .appendingPathComponent("SwiftDashSDK", isDirectory: true)
            .appendingPathComponent("Platform", isDirectory: true)
            .appendingPathComponent(network.networkName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("DashModel.sqlite", isDirectory: false)

        let configuration = ModelConfiguration(
            schema: DashModelContainer.schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none)
        return try ModelContainer(
            for: DashModelContainer.schema,
            configurations: [configuration])
    }
}
