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
//   - `createOrImportWallet(mnemonic:network:isImported:)` is the only path
//     that creates wallet rows and stores the mnemonic in WalletStorage.
//   - `stop()` releases the manager handle. Wipe-time persisted-row cleanup is
//     owned by `PlatformAddressSyncCoordinator` before BLAST stops.
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
        case walletCreationFailed(Error)
        case walletNotFound(AppNetwork)
        case invalidMnemonic
        case mnemonicPersistenceFailed(Error)
        case mnemonicRoundTripMismatch

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
            case .walletCreationFailed(let error):
                return "Wallet creation failed: \(error.localizedDescription)"
            case .walletNotFound(let network):
                return "No persisted SwiftDashSDK wallet found for \(network.rawValue)"
            case .invalidMnemonic:
                return "SwiftDashSDKHost received an invalid mnemonic"
            case .mnemonicPersistenceFailed(let error):
                return "Mnemonic persistence failed: \(error.localizedDescription)"
            case .mnemonicRoundTripMismatch:
                return "Mnemonic round-trip mismatch"
            }
        }
    }

    private struct RuntimeHandles {
        let sdk: SDK
        let manager: PlatformWalletManager
        let modelContainer: ModelContainer
        let network: AppNetwork
        let platformNetwork: PlatformNetwork
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

        Self.logger.info("🪺 HOST :: starting for \(network.rawValue, privacy: .public)")

        let handles = try buildRuntime(for: network)
        let resolvedWallet: ManagedPlatformWallet
        do {
            resolvedWallet = try loadPersistedWallet(manager: handles.manager, network: network)
        } catch let error as HostError {
            throw error
        } catch {
            Self.logger.error("🪺 HOST :: wallet bootstrap failed: \(String(describing: error), privacy: .public)")
            throw HostError.walletBootstrapFailed(error)
        }

        publish(handles: handles, wallet: resolvedWallet)
        Self.logger.info("🪺 HOST :: started for \(network.rawValue, privacy: .public)")
        return (handles.manager, resolvedWallet)
    }

    /// Create or import a wallet as the active managed platform wallet. This is
    /// the only path that writes new wallet identity into SwiftData and stores
    /// its mnemonic in `WalletStorage`.
    @discardableResult
    func createOrImportWallet(
        mnemonic: String,
        network: AppNetwork,
        isImported: Bool
    ) throws -> ManagedPlatformWallet {
        guard !mnemonic.isEmpty, Mnemonic.validate(mnemonic) else {
            throw HostError.invalidMnemonic
        }

        Self.logger.info("🪺 HOST :: creating managed wallet for \(network.rawValue, privacy: .public)")

        let handles = try buildRuntime(for: network)
        let createdWallet: ManagedPlatformWallet
        do {
            createdWallet = try handles.manager.createWallet(
                mnemonic: mnemonic,
                network: handles.platformNetwork,
                name: "dashwallet",
                createDefaultAccounts: true)
        } catch {
            Self.logger.error("🪺 HOST :: createWallet failed: \(String(describing: error), privacy: .public)")
            throw HostError.walletCreationFailed(error)
        }

        let storage = WalletStorage()
        do {
            try storage.storeMnemonic(mnemonic, for: createdWallet.walletId)
            let storedMnemonic = try storage.retrieveMnemonic(for: createdWallet.walletId)
            guard storedMnemonic == mnemonic else {
                throw HostError.mnemonicRoundTripMismatch
            }
        } catch {
            Self.logger.error("🪺 HOST :: mnemonic persistence failed: \(String(describing: error), privacy: .public)")
            try? storage.deleteMnemonic(for: createdWallet.walletId)
            deletePersistedWallet(walletId: createdWallet.walletId, in: handles.modelContainer)
            stop()
            if let hostError = error as? HostError {
                throw hostError
            }
            throw HostError.mnemonicPersistenceFailed(error)
        }

        publish(handles: handles, wallet: createdWallet)

        let origin = isImported ? "imported" : "created"
        Self.logger.info("🪺 HOST :: \(origin, privacy: .public) managed wallet for \(network.rawValue, privacy: .public)")
        return createdWallet
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

    // MARK: - Runtime bootstrap

    private func buildRuntime(for network: AppNetwork) throws -> RuntimeHandles {
        if manager != nil {
            stop()
        }

        guard let platformNetwork = platformNetwork(for: network) else {
            throw HostError.unsupportedNetwork(network)
        }

        Self.ensureSDKInitialized()

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

        return RuntimeHandles(
            sdk: newSDK,
            manager: newManager,
            modelContainer: container,
            network: network,
            platformNetwork: platformNetwork)
    }

    private func loadPersistedWallet(
        manager: PlatformWalletManager,
        network: AppNetwork
    ) throws -> ManagedPlatformWallet {
        let restored = try manager.loadFromPersistor()
        if let first = manager.firstWallet {
            Self.logger.info("🪺 HOST :: reusing persisted wallet; restored=\(restored.count, privacy: .public)")
            return first
        }

        throw HostError.walletNotFound(network)
    }

    private func publish(handles: RuntimeHandles, wallet resolvedWallet: ManagedPlatformWallet) {
        sdk = handles.sdk
        manager = handles.manager
        wallet = resolvedWallet
        modelContainer = handles.modelContainer
        runningNetwork = handles.network
    }

    private func deletePersistedWallet(walletId: Data, in container: ModelContainer) {
        let context = container.mainContext
        let descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate<PersistentWallet> { $0.walletId == walletId })
        do {
            let rows = try context.fetch(descriptor)
            for row in rows {
                context.delete(row)
            }
            try context.save()
            Self.logger.info("🪺 HOST :: rolled back \(rows.count, privacy: .public) persisted wallet row(s)")
        } catch {
            Self.logger.error("🪺 HOST :: persisted wallet rollback failed: \(String(describing: error), privacy: .public)")
        }
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
