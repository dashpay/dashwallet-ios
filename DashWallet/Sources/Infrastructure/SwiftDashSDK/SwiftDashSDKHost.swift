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
//   - `createOrImportWallet(mnemonic:network:origin:)` is the only path
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

enum MnemonicFirstWalletCreationError: Error {
    case mnemonicPersistence(Error)
    case mnemonicRoundTripMismatch
    case walletCreation(Error)
}

/// Process-lifetime cache used for network-scoped objects that must not be
/// opened twice over the same backing store. Generic so identity and network
/// separation can be tested without constructing SwiftData.
@MainActor
final class ProcessNetworkValueCache<Value> {
    private var values: [String: Value] = [:]

    func value(
        for networkKey: String,
        create: () throws -> Value
    ) rethrows -> (value: Value, reused: Bool) {
        if let existing = values[networkKey] {
            return (existing, true)
        }
        let created = try create()
        values[networkKey] = created
        return (created, false)
    }
}

/// Enforces the seed-safety ordering for wallet creation: persist and verify
/// the mnemonic before making the wallet live in a manager. If creation then
/// fails, only the provisional mnemonic is rolled back.
enum MnemonicFirstWalletCreation {
    static func run<Wallet>(
        mnemonic: String,
        persistMnemonic: () throws -> Void,
        retrieveMnemonic: () throws -> String,
        rollbackMnemonic: () -> Void,
        createWallet: () throws -> Wallet
    ) throws -> Wallet {
        do {
            try persistMnemonic()
            guard try retrieveMnemonic() == mnemonic else {
                rollbackMnemonic()
                throw MnemonicFirstWalletCreationError.mnemonicRoundTripMismatch
            }
        } catch let error as MnemonicFirstWalletCreationError {
            throw error
        } catch {
            rollbackMnemonic()
            throw MnemonicFirstWalletCreationError.mnemonicPersistence(error)
        }

        do {
            return try createWallet()
        } catch {
            rollbackMnemonic()
            throw MnemonicFirstWalletCreationError.walletCreation(error)
        }
    }
}

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
    private let modelContainerCache = ProcessNetworkValueCache<ModelContainer>()

    /// Watches for contact-crypto work that gets deferred *after* the
    /// load-time unlock. See `unlockDashPayContactCrypto`. Replaced (and the
    /// previous one cancelled) whenever a wallet is loaded, so only the active
    /// wallet is watched.
    private var contactCryptoDrainWatch: Task<Void, Never>?

    // MARK: - Process-wide SDK init guard

    private static var sdkInitialized = false
    private static let sdkInitLock = NSLock()

    static func ensureSDKInitialized() {
        sdkInitLock.lock()
        defer { sdkInitLock.unlock() }
        if !sdkInitialized {
            // Install the SDK's Rust tracing subscriber BEFORE init so
            // wallet-side diagnostics (DashPay sync passes, payment
            // reconciles, SPV events) are captured. Without this
            // every `tracing::warn!` in rs-platform-wallet is silently
            // dropped — the payments-attribution debugging session of
            // 2026-07-08 flew blind because of it. `RUST_LOG` overrides
            // the level when set (dev runs: SIMCTL_CHILD_RUST_LOG=…).
            //
            // `LoggingPreferences.configure()` installs FILE logging at
            // .info (simulator and device): one timestamped session
            // directory of per-crate `run.log` files per launch under
            // `Library/Logs/SwiftDashSDK/`, pruned by the SDK to 20
            // sessions / 100 MB. Nothing leaves the device — the
            // sessions exist so `DiagnosticLogExporter` (Tools → Export
            // Logs, support email) can bundle them when the user asks.
            // Falls back to console logging when the log root isn't
            // writable.
            LoggingPreferences.configure()
            SDK.initialize()
            sdkInitialized = true
        }
    }

    private init() {}

    // MARK: - Import scan floor

    /// Birth height for imported / unknown-provenance mnemonics, per
    /// network. Mainnet imports scan from block 200,000 rather than
    /// genesis (owner decision 2026-07-15): early-2015 and older
    /// blocks predate any wallet this app could import, so starting
    /// there skips a year of filter work without risking missed
    /// funds. Testnet (and anything else) scans from 0.
    static func importedWalletBirthHeight(for network: Network) -> UInt32 {
        network == .mainnet ? 200_000 : 0
    }

    // MARK: - Platform protocol version

    /// The `DashSDKConfig.platform_version` to build the SDK with, per network.
    ///
    /// **Testnet stays pinned to 13.** Testnet Drive moved past v12 to v13,
    /// whose validation set changed the shielded identity-create exit
    /// denominations (v12/V8 `[0.1, 0.3, 0.5, 1.0]` → v13/V9 `[0.03, 0.1,
    /// 0.25, 0.5, 1.0]`). Staying at v12 made the client build shielded
    /// transitions against the old set, so a contested (0.25 DASH) shielded
    /// username create failed client-side ("denomination 25000000000 is not a
    /// member …") even though the server requires exactly 0.25. Pinning
    /// explicitly also avoids a race where the shielded build runs before the
    /// SDK has ratcheted to the network version. Bump this when the agreed
    /// testnet protocol moves past v13.
    ///
    /// **Mainnet uses `0` — auto-detect.** The pin above was chosen for
    /// testnet but applied to every network, which put the client two versions
    /// ahead of mainnet. Platform v13 (`DRIVE_VERSION_V8`) switches the
    /// compacted address-balance proof to the two-proof
    /// `CompactedAddressBalanceProof` bincode envelope, while "nodes and
    /// clients on v12 and below keep the legacy single GroveDB proof"
    /// (rs-platform-version `version/v13.rs`). A v13 client therefore decodes
    /// mainnet's legacy proof as the envelope, consumes the structure and
    /// trips on the remainder:
    ///
    ///     proof: corrupted error: compacted address balance proof contains trailing bytes
    ///
    /// — observed 20× across three nodes on a mainnet device (2026-07-31),
    /// with testnet clean, and it retries then gives up, so the Platform
    /// address balance never populates there.
    ///
    /// `0` is what the SDK is designed for: it seeds at the per-network
    /// `min_protocol_version` floor (mainnet 11, testnet 12) with auto-detect
    /// on, ratcheting up as the network reports newer versions — "so this
    /// picks the right wire without a Swift-side network→version map"
    /// (`SDK.init(network:platformVersion:)`). A hard pin also disables
    /// `refreshProtocolVersion()`, which is documented as a no-op while
    /// pinned, so the client could never learn the network's real version.
    ///
    /// Devnet/regtest follow mainnet's auto-detect: no shielded-denomination
    /// contract is pinned for them, and `makeRuntime` rejects regtest anyway.
    static func platformVersion(for network: Network) -> UInt32 {
        network == .testnet ? 13 : 0
    }

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
        Self.logger.info("🪺 HOST :: stage 4/4 restoring wallet for \(network.rawValue, privacy: .public)")
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
        Self.logger.info("🪺 HOST :: stage 4/4 wallet restored for \(network.rawValue, privacy: .public)")
        Self.logger.info("🪺 HOST :: started for \(network.rawValue, privacy: .public)")
        return (handles.manager, resolvedWallet)
    }

    /// Create or import a wallet as the SOLE active managed platform wallet.
    /// This is the fresh-install / recover path: it rebuilds the runtime from
    /// scratch (`buildRuntime` tears down any running manager), stores and
    /// verifies its mnemonic, creates the wallet, pins it active in the registry, and
    /// publishes it as bound. Onboarding's first wallet uses this.
    ///
    /// For adding a wallet ALONGSIDE existing ones without rebinding the
    /// active wallet, use `addWallet(mnemonic:origin:)` instead — this path replaces
    /// the running runtime and is not additive.
    @discardableResult
    func createOrImportWallet(
        mnemonic: String,
        network: Network,
        origin: WalletMaterialOrigin
    ) async throws -> ManagedPlatformWallet {
        guard !mnemonic.isEmpty, Mnemonic.validate(mnemonic) else {
            throw HostError.invalidMnemonic
        }

        Self.logger.info("🪺 HOST :: creating managed wallet for \(network.rawValue, privacy: .public)")

        let handles = try buildRuntime(for: network)
        let createdWallet: ManagedPlatformWallet
        do {
            createdWallet = try createAndPersist(
                mnemonic: mnemonic,
                manager: handles.manager,
                network: handles.network,
                // Imported mnemonics may hold history from long before
                // this device: scan from the network's import floor
                // (genesis on testnet, block 200,000 on mainnet — see
                // `importedWalletBirthHeight`). Freshly generated
                // mnemonics keep nil — nothing can predate them, so
                // the scan anchors at the tip.
                birthHeight: origin.scansHistoricalRange
                    ? Self.importedWalletBirthHeight(for: handles.network)
                    : nil)
        } catch {
            // `createOrImportWallet` owns a freshly-built (not yet published)
            // runtime, so tear it down on failure. `createAndPersist` has
            // already rolled back any provisional mnemonic it wrote.
            stop()
            throw error
        }

        if origin.armsInitialRestoreSync {
            InitialRestoreSyncStore.shared.markImportedIfNeeded(walletId: createdWallet.walletId)
        }
        if let kind = registryNetworkKind(for: network) {
            WalletEnvironment.setActiveWalletId(createdWallet.walletId, for: kind)
        }
        publish(handles: handles, wallet: createdWallet)

        Self.logger.info("🪺 HOST :: \(String(describing: origin), privacy: .public) managed wallet for \(network.rawValue, privacy: .public)")
        return createdWallet
    }

    /// Outcome of `addWallet(mnemonic:origin:)`.
    enum AddWalletResult {
        /// The wallet was created and its mnemonic persisted; the running
        /// runtime is unchanged (the caller switches to it explicitly).
        case added(walletId: Data)
        /// A wallet deriving this walletId already has a persisted mnemonic on
        /// this device — nothing was written. The caller offers switching to it.
        case alreadyExists(walletId: Data)
    }

    /// Add a wallet from `mnemonic` ADDITIVELY: create it in the already-running
    /// manager and persist its mnemonic, WITHOUT tearing down the runtime,
    /// touching the active-wallet registry, or rebinding the published active
    /// wallet. The caller (Wallets screen "Add Wallet") switches to the new
    /// wallet afterward via `SwiftDashSDKWalletRuntime.switchWallet`.
    ///
    /// Requires a running host (a bound active wallet already exists — adding
    /// is only reachable from the Wallets screen). Returns `.alreadyExists`
    /// without writing anything when a mnemonic for the derived walletId is
    /// already persisted (`manager.createWallet` is idempotent by walletId, so
    /// re-adding would silently no-op — the caller surfaces this instead).
    ///
    /// Shares the persist-then-create transaction with
    /// `createOrImportWallet` (`createAndPersist`); differs only in that it
    /// uses the LIVE manager and does not publish or set-active.
    @discardableResult
    func addWallet(mnemonic: String, origin: WalletMaterialOrigin) async throws -> AddWalletResult {
        guard !mnemonic.isEmpty, Mnemonic.validate(mnemonic) else {
            throw HostError.invalidMnemonic
        }
        guard let manager = manager,
              modelContainer != nil,
              let network = runningNetwork else {
            throw HostError.walletNotFound(runningNetwork ?? .mainnet)
        }

        // Idempotence guard: `createWallet` is keyed by the deterministic
        // walletId, so adding an already-present wallet would no-op. Detect it
        // from the persisted-mnemonic set (the switchable-wallet source of
        // truth) and report `.alreadyExists` rather than a fabricated success.
        let derivedId = try Wallet(mnemonic: mnemonic, network: network).id
        if Self.persistedMnemonics().contains(where: { $0.walletId == derivedId }) {
            Self.logger.info("🪺 HOST :: addWallet — walletId already persisted; not re-adding")
            return .alreadyExists(walletId: derivedId)
        }

        let createdWallet = try createAndPersist(
            mnemonic: mnemonic,
            manager: manager,
            network: network,
            // Same semantics as `createOrImportWallet`: imports scan
            // from the network's import floor, freshly generated
            // wallets from the tip.
            birthHeight: origin.scansHistoricalRange
                ? Self.importedWalletBirthHeight(for: network)
                : nil)

        if origin.armsInitialRestoreSync {
            InitialRestoreSyncStore.shared.markImportedIfNeeded(walletId: createdWallet.walletId)
        }

        Self.logger.info("🪺 HOST :: added managed wallet for \(network.rawValue, privacy: .public) (additive)")
        return .added(walletId: createdWallet.walletId)
    }

    /// Derive the deterministic wallet id, persist and verify its mnemonic, then
    /// create the wallet in `manager`. The manager is never touched when secret
    /// persistence fails; a later create failure removes only the provisional
    /// mnemonic. Does NOT touch the registry, publish, or stop the host —
    /// runtime bookkeeping is the caller's (so this body is shared by the
    /// rebuild path `createOrImportWallet` and the additive `addWallet`).
    /// `birthHeight` follows the SDK's `createWallet` contract: `nil`
    /// anchors the SPV scan at the current tip (fresh mnemonic — with
    /// unsynced headers the SDK falls back to the network's newest
    /// hardcoded checkpoint), `0` scans from genesis (imported mnemonic
    /// whose history predates this device).
    private func createAndPersist(
        mnemonic: String,
        manager: PlatformWalletManager,
        network: Network,
        birthHeight: UInt32?
    ) throws -> ManagedPlatformWallet {
        let walletId: Data
        do {
            // This is the same deterministic id contract used by addWallet's
            // duplicate guard and PlatformWalletManager.createWallet.
            walletId = try Wallet(mnemonic: mnemonic, network: network).id
        } catch {
            Self.logger.error("🪺 HOST :: walletId derivation failed: \(String(describing: error), privacy: .public)")
            throw HostError.walletCreationFailed(error)
        }

        let storage = WalletStorage()
        let previousMnemonic: String?
        do {
            previousMnemonic = try storage.retrieveMnemonic(for: walletId)
        } catch WalletStorageError.mnemonicNotFound {
            previousMnemonic = nil
        } catch {
            Self.logger.error("🪺 HOST :: existing mnemonic lookup failed: \(String(describing: error), privacy: .public)")
            throw HostError.mnemonicPersistenceFailed(error)
        }

        do {
            return try MnemonicFirstWalletCreation.run(
                mnemonic: mnemonic,
                persistMnemonic: {
                    try storage.storeMnemonic(mnemonic, for: walletId)
                },
                retrieveMnemonic: {
                    try storage.retrieveMnemonic(for: walletId)
                },
                rollbackMnemonic: {
                    if let previousMnemonic {
                        try? storage.storeMnemonic(previousMnemonic, for: walletId)
                    } else {
                        try? storage.deleteMnemonic(for: walletId)
                    }
                },
                createWallet: {
                    try manager.createWallet(
                        mnemonic: mnemonic,
                        network: network,
                        name: "dashwallet",
                        createDefaultAccounts: true,
                        birthHeight: birthHeight)
                })
        } catch MnemonicFirstWalletCreationError.mnemonicRoundTripMismatch {
            Self.logger.error("🪺 HOST :: mnemonic persistence round-trip mismatch")
            throw HostError.mnemonicRoundTripMismatch
        } catch MnemonicFirstWalletCreationError.mnemonicPersistence(let error) {
            Self.logger.error("🪺 HOST :: mnemonic persistence failed: \(String(describing: error), privacy: .public)")
            throw HostError.mnemonicPersistenceFailed(error)
        } catch MnemonicFirstWalletCreationError.walletCreation(let error) {
            Self.logger.error("🪺 HOST :: createWallet failed: \(String(describing: error), privacy: .public)")
            throw HostError.walletCreationFailed(error)
        } catch {
            // The transaction exhaustively maps its own failures; keep an
            // explicit fallback so a future case cannot escape untyped.
            Self.logger.error("🪺 HOST :: wallet creation transaction failed: \(String(describing: error), privacy: .public)")
            if let hostError = error as? HostError {
                throw hostError
            }
            throw HostError.walletCreationFailed(error)
        }
    }

    /// Tear down the host's active references. The per-network
    /// `ModelContainer` remains process-cached so a later runtime rebuild does
    /// not open a second container over the same SQLite store.
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

        return try makeRuntime(for: network)
    }

    /// Build a configured manager/container pair without replacing the
    /// published app runtime. Full-device wipe uses this for the inactive
    /// network so each network-scoped SwiftData store is deleted through a
    /// manager configured for that same network.
    private func makeRuntime(for network: Network) throws -> RuntimeHandles {
        guard network != .regtest else {
            throw HostError.unsupportedNetwork(network)
        }

        Self.ensureSDKInitialized()
        Self.logger.info("🪺 HOST :: stage 1/4 creating SDK for \(network.rawValue, privacy: .public)")

        let newSDK: SDK
        do {
            let platformVersion = Self.platformVersion(for: network)
            newSDK = try SDK(network: network, platformVersion: platformVersion)
            Self.logger.info(
                "🪺 HOST :: stage 1/4 SDK created for \(network.rawValue, privacy: .public), protocol \(platformVersion == 0 ? "auto-detect" : "pinned v\(platformVersion)", privacy: .public)")
        } catch {
            Self.logger.error("🪺 HOST :: SDK init failed: \(String(describing: error), privacy: .public)")
            throw HostError.sdkInitFailed(error)
        }

        let container: ModelContainer
        do {
            Self.logger.info("🪺 HOST :: stage 2/4 obtaining ModelContainer for \(network.rawValue, privacy: .public)")
            let cached = try modelContainerCache.value(for: network.networkName) {
                try buildModelContainer(for: network)
            }
            container = cached.value
            Self.logger.info("🪺 HOST :: stage 2/4 ModelContainer \(cached.reused ? "reused" : "created", privacy: .public) for \(network.rawValue, privacy: .public)")
        } catch {
            Self.logger.error("🪺 HOST :: ModelContainer build failed: \(String(describing: error), privacy: .public)")
            throw HostError.modelContainerFailed(error)
        }

        let newManager = PlatformWalletManager()
        do {
            Self.logger.info("🪺 HOST :: stage 3/4 configuring manager for \(network.rawValue, privacy: .public)")
            try newManager.configure(sdk: newSDK, modelContainer: container)
            Self.logger.info("🪺 HOST :: stage 3/4 manager configured for \(network.rawValue, privacy: .public)")
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

    /// Manager bound to `network` for full-device wipe.
    ///
    /// The live manager is reused for its network. The other network gets a
    /// detached manager over the process-cached `ModelContainer`, avoiding a
    /// second open of the same SQLite store and leaving the published runtime
    /// unchanged until the wipe commits.
    func managerForWipe(network: Network) throws -> PlatformWalletManager {
        if runningNetwork == network, let manager {
            return manager
        }

        let handles = try makeRuntime(for: network)
        _ = try handles.manager.loadFromPersistor()
        return handles.manager
    }

    private func loadPersistedWallet(
        manager: PlatformWalletManager,
        network: Network
    ) throws -> ManagedPlatformWallet {
        let restored = try manager.loadFromPersistor()
        if let resolved = resolveActiveWallet(in: manager, network: network) {
            Self.logger.info("🪺 HOST :: reusing persisted wallet; restored=\(restored.count, privacy: .public)")
            // Off the load path. `PlatformWalletManager` is `@MainActor`, so
            // the unlock's Keychain read and its two synchronous FFI calls run
            // on the main thread whenever they run; scheduling them as their
            // own main-actor turn at least keeps them out of wallet load,
            // which is on the launch critical path.
            Task { [weak self] in
                self?.unlockDashPayContactCrypto(manager: manager, wallet: resolved)
            }
            return resolved
        }

        throw HostError.walletNotFound(network)
    }

    /// Complete the contact crypto that `loadFromPersistor` had to defer.
    ///
    /// A persisted restore rehydrates the wallet external-signable — per-account
    /// xpubs, no key material. The DashPay contact sweep needs a signer to ECDH
    /// each contact's encrypted xpub into a `DashpayExternalAccount`, so with no
    /// signer present it enqueues the build instead ("Deferred DashPay account
    /// build") and re-enqueues it every sweep. Until something drains that queue
    /// the wallet has no external accounts, which means no derived contact
    /// addresses: sent-payment history cannot be reconstructed after a restore,
    /// and the contact card stays on "No payments with this contact yet".
    ///
    /// `send_payment` drains the queue with its own signer, so the gap only
    /// showed on wallets that had not sent to the contact since restoring.
    /// This is the signer-backed drain the SDK documents on
    /// `unlockWalletFromKeychain`; the drain itself re-fetches over the network
    /// and runs detached, so the call returns immediately.
    ///
    /// Best-effort by design — a failure here must not fail wallet load. It
    /// returns `false` for a genuine watch-only wallet (no stored mnemonic) and
    /// throws only when the resolved seed does not bind to this wallet, which is
    /// worth a log line but not a launch failure.
    ///
    /// Logged through `DWLogger` rather than `os_log` on purpose: this line has
    /// to survive into the `app-logs/` group of a diagnostic export, and the
    /// `os-log.txt` capture is not on this branch. It reports the three states
    /// that tell apart the ways the drain can fail to happen — no stored
    /// mnemonic for this wallet id (unlock no-ops), an empty queue (nothing was
    /// deferred), and a seed that does not bind (throws).
    private func unlockDashPayContactCrypto(
        manager: PlatformWalletManager,
        wallet: ManagedPlatformWallet
    ) {
        let walletId = wallet.walletId
        let idTag = walletId.prefix(4).map { String(format: "%02x", $0) }.joined()
        // Existence-only probe on the active wallet's own id — the same check
        // `unlockWalletFromKeychain` makes internally, surfaced so a `false`
        // return is distinguishable from "never called". No plaintext is read.
        let hasMnemonic = WalletStorage().hasMnemonic(for: walletId)
        let pending = (try? manager.pendingAccountBuildCount(for: walletId)).map(String.init) ?? "n/a"
        do {
            // Timed because it is main-thread work: the seed-binding verify is
            // marker-cached, but a cache miss re-derives the BIP44 account-0
            // xpub through the Keychain resolver. If a UI stall lines up with
            // this line, that is the cost.
            let started = CFAbsoluteTimeGetCurrent()
            let unlocked = try manager.unlockWalletFromKeychain(wallet)
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            DWLogger.log(
                "DashPay unlock: wallet=\(idTag) hasMnemonic=\(hasMnemonic) pendingAccountBuilds=\(pending) unlocked=\(unlocked) tookMs=\(ms)")
        } catch {
            DWLogger.log(
                "DashPay unlock FAILED: wallet=\(idTag) hasMnemonic=\(hasMnemonic) pendingAccountBuilds=\(pending) error=\(String(describing: error))")
        }

        // A single unlock at load time is not enough: it schedules the drain
        // only when the queue is already non-empty, and at this point it is
        // empty — the contact sweep that defers the account builds has not run
        // yet. Measured on a restored wallet: 0 pending at unlock, 4 pending
        // 45s later, and nothing to drain them. So keep watching and unlock
        // again once work appears. Re-unlocking is cheap — the seed-binding
        // verify is marker-cached after the first success.
        contactCryptoDrainWatch?.cancel()
        contactCryptoDrainWatch = Task { [weak self] in
            // Bounded: a queue that survives its drains is a failure to report,
            // not something to retry forever.
            var attemptsLeft = 5
            var drained = false
            for await statuses in manager.$dashPayUnlockStatus.values {
                if Task.isCancelled || self == nil { return }
                guard let status = statuses[walletId] else { continue }
                if status.pendingAccountBuilds == 0, !status.draining {
                    guard drained else { continue }
                    // The contact accounts exist now. Sweep immediately rather
                    // than waiting out the DashPay sync interval — that wait is
                    // most of why a restored wallet showed an empty contact
                    // card on first open and its history only on a later one.
                    DWLogger.log("DashPay unlock: wallet=\(idTag) drain complete; syncing now")
                    await SwiftDashSDKContactsService.shared.syncNow()
                    return
                }
                guard status.pendingAccountBuilds > 0, !status.draining else { continue }
                guard attemptsLeft > 0 else {
                    DWLogger.log(
                        "DashPay unlock: wallet=\(idTag) giving up with \(status.pendingAccountBuilds) pending account build(s)")
                    return
                }
                attemptsLeft -= 1
                do {
                    let started = CFAbsoluteTimeGetCurrent()
                    let unlocked = try manager.unlockWalletFromKeychain(wallet)
                    let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
                    DWLogger.log(
                        "DashPay unlock: wallet=\(idTag) draining \(status.pendingAccountBuilds) deferred build(s); unlocked=\(unlocked) tookMs=\(ms)")
                    drained = true
                } catch {
                    DWLogger.log(
                        "DashPay unlock: wallet=\(idTag) re-unlock failed: \(String(describing: error))")
                    return
                }
                // Let `draining` publish before the next element is considered,
                // so one drain isn't counted as several attempts.
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// `WalletEnvironment.NetworkKind` for the SDK `Network` — the app-side
    /// key the active-wallet registry is scoped by. Only `.mainnet` /
    /// `.testnet` reach the registry; `.devnet`/`.regtest` don't run a
    /// persisted wallet (`buildRuntime` rejects `.regtest`), so they map to
    /// `nil` and the resolver falls back to `firstWallet` without touching
    /// the registry.
    private func registryNetworkKind(for network: Network) -> WalletEnvironment.NetworkKind? {
        switch network {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        default: return nil
        }
    }

    /// Resolve which loaded wallet is active for `network`: the persisted
    /// `WalletEnvironment.activeWalletId` when it names a wallet the manager
    /// currently holds, otherwise `firstWallet` (unset registry, or the
    /// recorded wallet is gone). The resolved walletId is written back to the
    /// registry so it's concrete after the first launch — including the
    /// fallback, which pins the arbitrary-but-deterministic `firstWallet` as
    /// the active choice going forward. Returns `nil` only when the manager
    /// holds no wallets at all.
    private func resolveActiveWallet(
        in manager: PlatformWalletManager,
        network: Network
    ) -> ManagedPlatformWallet? {
        let kind = registryNetworkKind(for: network)
        if let kind,
           let activeId = WalletEnvironment.activeWalletId(for: kind),
           let active = manager.wallets[activeId] {
            return active
        }
        guard let fallback = manager.firstWallet else { return nil }
        if let kind {
            WalletEnvironment.setActiveWalletId(fallback.walletId, for: kind)
        }
        return fallback
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
                let derivedId = try Wallet(
                    mnemonic: entry.mnemonic,
                    network: handles.network).id
                let wasMissingLocally = handles.manager.wallets[derivedId] == nil
                let created = try handles.manager.createWallet(
                    mnemonic: entry.mnemonic,
                    network: handles.network,
                    name: "dashwallet",
                    createDefaultAccounts: true,
                    // This path registers a keychain mnemonic whose
                    // SwiftData rows are gone (reinstall) or never
                    // existed on this network (first switch). Its true
                    // creation height is unknown and the wallet may
                    // hold history from long before this registration,
                    // so scan from the network's import floor — the
                    // conservative-correct choice; a needless full
                    // scan is recoverable, a tip-anchored miss of old
                    // funds is not.
                    birthHeight: Self.importedWalletBirthHeight(for: handles.network))
                if created.walletId != entry.walletId {
                    try? storage.storeMnemonic(entry.mnemonic, for: created.walletId)
                    InitialRestoreSyncStore.shared.remove(walletId: entry.walletId)
                }
                if wasMissingLocally {
                    InitialRestoreSyncStore.shared.markReconstructed(walletId: created.walletId)
                }
            } catch {
                Self.logger.error("🪺 HOST :: keychain wallet recovery failed for one entry: \(String(describing: error), privacy: .public)")
            }
        }

        guard let resolved = resolveActiveWallet(in: handles.manager, network: handles.network) else { return nil }
        Self.logger.info("🪺 HOST :: recovered persisted wallet from keychain mnemonic(s); entries=\(entries.count, privacy: .public)")
        return resolved
    }

    private func publish(handles: RuntimeHandles, wallet resolvedWallet: ManagedPlatformWallet) {
        sdk = handles.sdk
        manager = handles.manager
        wallet = resolvedWallet
        modelContainer = handles.modelContainer
        runningNetwork = handles.network
        CoreSpendAvailability.shared.refresh()
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
