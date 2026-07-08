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
    private(set) var runningNetwork: Network?

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

    // MARK: - Wallet presence

    /// True when at least one SDK wallet mnemonic is persisted in
    /// `WalletStorage`'s keychain (global — the mnemonic is network-agnostic;
    /// survives app reinstall). The app's sanctioned presence reader: FFI-free
    /// (a plain SecItem query), valid before `start()` and from any thread —
    /// the same posture as the KeyMigrator/WalletWiper storage reads. A
    /// keychain read error reports as "no wallet" (logged); app-level checks
    /// union this with DashSync presence (`WalletEnvironment.hasWallet`) for
    /// the migration window.
    nonisolated static func hasPersistedSDKWallet() -> Bool {
        do {
            return try !WalletStorage().listWalletIdsWithMnemonic().isEmpty
        } catch {
            logger.error("🪺 HOST :: wallet-presence keychain read failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    /// Every persisted SDK wallet mnemonic, keyed by its stored walletId —
    /// the same `WalletStorage` keychain surface `hasPersistedSDKWallet` reads.
    /// Consumers: reinstall recovery (`start`'s `walletNotFound` retry) and
    /// the wipe-with-phrase comparison. A keychain error reads as empty
    /// (logged); an entry whose mnemonic can't be retrieved is skipped.
    nonisolated static func persistedMnemonics() -> [(walletId: Data, mnemonic: String)] {
        do {
            let storage = WalletStorage()
            return try storage.listWalletIdsWithMnemonic().compactMap { walletId in
                guard let mnemonic = try? storage.retrieveMnemonic(for: walletId),
                      !mnemonic.isEmpty else { return nil }
                return (walletId: walletId, mnemonic: mnemonic)
            }
        } catch {
            logger.error("🪺 HOST :: mnemonic keychain enumeration failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// Throwaway key-wallet stack (manager + wallet) for path-based key
    /// derivation, built from the persisted mnemonic of the host's active
    /// wallet. Separate from the running `PlatformWalletManager` — key
    /// derivation lives in the `WalletManager`/`Wallet` FFI surface, which
    /// the runtime handles don't expose. The instances derive keys locally
    /// (no networking, no persistence); drop them when done.
    ///
    /// Consumers: the masternode Owner/Voting key deriver and CrowdNode
    /// message signing. Returns nil when no wallet is bound/running or the
    /// mnemonic can't be read (logged).
    func derivationWallet() -> (manager: WalletManager, wallet: Wallet, walletId: Data)? {
        guard let hostWalletId = wallet?.walletId, let network = runningNetwork else {
            Self.logger.warning("🪺 HOST :: derivationWallet — no bound wallet/network")
            return nil
        }
        guard let mnemonic = try? WalletStorage().retrieveMnemonic(for: hostWalletId),
              let manager = try? WalletManager(network: network),
              let walletId = try? manager.addWallet(mnemonic: mnemonic),
              let derivationWallet = (try? manager.getWallet(id: walletId)) ?? nil else {
            Self.logger.error("🪺 HOST :: derivationWallet — key-wallet bootstrap failed")
            return nil
        }
        return (manager: manager, wallet: derivationWallet, walletId: walletId)
    }

    // MARK: - Lifecycle

    enum HostError: LocalizedError {
        case unsupportedNetwork(Network)
        case sdkInitFailed(Error)
        case modelContainerFailed(Error)
        case configureFailed(Error)
        case walletBootstrapFailed(Error)
        case walletCreationFailed(Error)
        case walletNotFound(Network)
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
        let network: Network
    }

    /// Start the host for `network`. Idempotent: re-entering with the same
    /// network leaves the live manager + wallet alone. Different network
    /// triggers a clean rebuild via `stop()` first.
    @discardableResult
    func start(network: Network) throws -> (manager: PlatformWalletManager, wallet: ManagedPlatformWallet) {
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
        } catch HostError.walletNotFound {
            // Reinstall recovery (C6-C): the SwiftData store dies with the app
            // but WalletStorage mnemonics live in the keychain — rebuild the
            // wallet rows from them instead of failing the start. Before this,
            // reinstall+Keep only worked when the KeyMigrator's async re-import
            // happened to win the race against this load.
            guard let recovered = recoverPersistedWallet(handles: handles) else {
                throw HostError.walletNotFound(network)
            }
            resolvedWallet = recovered
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
        network: Network,
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
                network: handles.network,
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

    private func buildRuntime(for network: Network) throws -> RuntimeHandles {
        if manager != nil {
            stop()
        }

        guard network != .regtest else {
            throw HostError.unsupportedNetwork(network)
        }

        Self.ensureSDKInitialized()

        let newSDK: SDK
        do {
            // Pin Platform protocol version 12. v12 is the current server
            // version and the floor for shielded transitions —
            // `ShieldFromAssetLock` / `Shield` fees were introduced in v12,
            // and pinning v11 made the client compute a stale, too-low
            // shielded pool fee (testnet rejected the asset lock as
            // underfunded, "needs … credits to start processing"). Pinning
            // explicitly rather than relying on the auto-detect default
            // (`platformVersion: 0`, which floors at mainnet 11 / testnet 12)
            // keeps the wire format consistent across networks. The knob is
            // the `DashSDKConfig.platform_version` field (dashpay/platform
            // #3751); bump this when the agreed protocol moves past v12.
            newSDK = try SDK(network: network, platformVersion: 12)
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
            network: network)
    }

    private func loadPersistedWallet(
        manager: PlatformWalletManager,
        network: Network
    ) throws -> ManagedPlatformWallet {
        let restored = try manager.loadFromPersistor()
        if let first = manager.firstWallet {
            Self.logger.info("🪺 HOST :: reusing persisted wallet; restored=\(restored.count, privacy: .public)")
            return first
        }

        throw HostError.walletNotFound(network)
    }

    /// `walletNotFound` retry: re-create wallet rows from the keychain
    /// mnemonics (`persistedMnemonics`). One attempt per entry, no retry loop —
    /// `createWallet` is idempotent by walletId (`Wallet(mnemonic:network:).id`),
    /// so a re-run after a partial failure converges. The mnemonic is re-stored
    /// under the created walletId when the stored key was derived for a
    /// different network (mnemonics are network-agnostic; ids aren't).
    /// Wipe race note: the wiper deletes mnemonics before `handleWalletWiped`,
    /// so a refresh racing a wipe finds an empty list here and fails the start
    /// — and the next refresh's `hasSDKWallet` gate stays closed.
    private func recoverPersistedWallet(handles: RuntimeHandles) -> ManagedPlatformWallet? {
        let entries = Self.persistedMnemonics()
        guard !entries.isEmpty else { return nil }

        let storage = WalletStorage()
        for entry in entries {
            guard Mnemonic.validate(entry.mnemonic) else {
                Self.logger.error("🪺 HOST :: skipping keychain mnemonic for \(entry.walletId.prefix(4).map { String(format: "%02x", $0) }.joined(), privacy: .public)… — failed validation")
                continue
            }
            do {
                let created = try handles.manager.createWallet(
                    mnemonic: entry.mnemonic,
                    network: handles.network,
                    name: "dashwallet",
                    createDefaultAccounts: true)
                if created.walletId != entry.walletId {
                    try? storage.storeMnemonic(entry.mnemonic, for: created.walletId)
                }
            } catch {
                Self.logger.error("🪺 HOST :: keychain wallet recovery failed for one entry: \(String(describing: error), privacy: .public)")
            }
        }

        guard let first = handles.manager.firstWallet else { return nil }
        Self.logger.info("🪺 HOST :: recovered persisted wallet from keychain mnemonic(s); entries=\(entries.count, privacy: .public)")
        return first
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

    // MARK: - ModelContainer

    private func buildModelContainer(for network: Network) throws -> ModelContainer {
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

    /// Filesystem path for the per-network shielded Orchard commitment-tree
    /// SQLite file, handed to `PlatformWalletManager.configureShielded(dbPath:)`.
    /// Mirrors `buildModelContainer`'s `documents/SwiftDashSDK/<subsystem>/<network>/`
    /// convention in a sibling `Shielded/` directory; creates the directory if
    /// needed. The manager is rebuilt per network (`buildRuntime`), so a
    /// per-network path keeps `configureShielded` idempotent — it throws only
    /// when re-pointed to a different path on the same manager.
    func shieldedTreeDBPath(for network: Network) throws -> String {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        let dir = documents
            .appendingPathComponent("SwiftDashSDK", isDirectory: true)
            .appendingPathComponent("Shielded", isDirectory: true)
            .appendingPathComponent(network.networkName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true)
        return dir
            .appendingPathComponent("commitment-tree.sqlite", isDirectory: false)
            .path
    }
}
