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
//   - `stopAsync()` shuts the manager down off-main (blocking native
//     teardown on the SDK's destroy queue) and only then releases the
//     references. Wipe-time persisted-row cleanup is owned by
//     `PlatformAddressSyncCoordinator` before BLAST stops.
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
        createWallet: () async throws -> Wallet
    ) async throws -> Wallet {
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
            return try await createWallet()
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
    /// Consumers: reinstall recovery (`start`'s `walletNotFound` retry),
    /// switchable-wallet discovery, and non-destructive phrase checks. A
    /// keychain error reads as empty (logged); an entry whose mnemonic can't
    /// be retrieved is skipped. Destructive authorization uses the strict
    /// variant below.
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

    /// Strict variant for destructive authorization. Unlike
    /// `persistedMnemonics()`, this throws when enumeration OR any individual
    /// mnemonic read fails, so callers cannot mistake a partially readable
    /// Keychain for the complete wallet set.
    nonisolated static func strictlyPersistedMnemonics() throws -> [(walletId: Data, mnemonic: String)] {
        let storage = WalletStorage()
        return try storage.listWalletIdsWithMnemonic().map { walletId in
            let mnemonic = try storage.retrieveMnemonic(for: walletId)
            return (walletId: walletId, mnemonic: mnemonic)
        }
    }

    /// Networks represented by a strict SDK-owned Keychain inventory. Used
    /// after reinstall to select a sole stored network without manufacturing
    /// a network mirror from the same seed.
    nonisolated static func persistedSDKWalletNetworks(
        in entries: [(walletId: Data, mnemonic: String)]
    ) throws -> Set<Network> {
        try Set(entries.map { entry in
            try SwiftDashSDKStoredWalletNetworkResolver.resolve(
                walletId: entry.walletId,
                mnemonic: entry.mnemonic
            ).network
        })
    }

    nonisolated static func persistedSDKWalletNetworks() throws -> Set<Network> {
        try persistedSDKWalletNetworks(in: strictlyPersistedMnemonics())
    }

    /// Pure filtering used by reinstall recovery: a manager must only receive
    /// entries whose deterministic id belongs to that manager's network.
    nonisolated static func recoverablePersistedMnemonics(
        _ entries: [(walletId: Data, mnemonic: String)],
        for network: Network
    ) -> [(walletId: Data, mnemonic: String)] {
        entries.compactMap { entry in
            let mnemonic = Mnemonic.normalizePhrase(entry.mnemonic)
            guard Mnemonic.validate(mnemonic),
                  let resolution = try? SwiftDashSDKStoredWalletNetworkResolver.resolve(
                      walletId: entry.walletId,
                      mnemonic: mnemonic),
                  resolution.network == network else {
                return nil
            }
            return (walletId: entry.walletId, mnemonic: mnemonic)
        }
    }

    /// Strict exact-id read for flows that already selected a concrete wallet.
    /// Unlike the legacy active-wallet reader, this never substitutes another
    /// Keychain entry when the requested id is missing or unreadable.
    nonisolated static func strictlyPersistedMnemonic(for walletId: Data) throws -> String {
        try WalletStorage().retrieveMnemonic(for: walletId)
    }

    /// Count of persisted SDK wallet ids. Attributes-only Keychain
    /// enumeration — no mnemonic secrets are read. Throws on enumeration
    /// failure so destructive callers stay fail-closed.
    nonisolated static func persistedWalletIdCount() throws -> Int {
        try WalletStorage().listWalletIdsWithMnemonic().count
    }

    /// Number of logical wallets represented by the strict Keychain inventory.
    /// The same recovery phrase may be stored under separate network-scoped
    /// wallet ids; those entries count as one wallet in destructive UI copy.
    /// Throws when enumeration or any mnemonic read fails so callers can fall
    /// back to non-destructive retry/keep actions.
    nonisolated static func distinctStoredWalletCount() throws -> Int {
        distinctWalletCount(in: try strictlyPersistedMnemonics())
    }

    /// Pure logical-wallet count used after a strict inventory read. Separate
    /// network-scoped ids carrying the same normalized phrase are one wallet.
    nonisolated static func distinctWalletCount(
        in entries: [(walletId: Data, mnemonic: String)]
    ) -> Int {
        let phrases = entries.map {
            Mnemonic.normalizePhrase($0.mnemonic)
        }
        return Set(phrases).count
    }

    /// Set-wide destructive-authorization predicate: true only when `phrase`,
    /// normalized, matches EVERY strictly readable stored mnemonic (multiple
    /// network-scoped ids for one seed all carry the same phrase and match).
    /// False for an empty normalized phrase or an empty wallet set —
    /// `allSatisfy` on `[]` is vacuously true, and a walletless install must
    /// never authorize a wipe. Throws when enumeration or any individual
    /// mnemonic read fails. Consumers: `canWipeWithPhrase` and the
    /// Wallets-screen reset routing.
    nonisolated static func allStoredMnemonicsMatch(phrase: String) throws -> Bool {
        try allMnemonicsMatch(phrase: phrase, in: strictlyPersistedMnemonics())
    }

    /// Core of `allStoredMnemonicsMatch(phrase:)` over pre-fetched `entries`,
    /// for callers that already hold the strict enumeration (avoids a second
    /// Keychain pass).
    nonisolated static func allMnemonicsMatch(
        phrase: String, in entries: [(walletId: Data, mnemonic: String)]) -> Bool {
        let typed = Mnemonic.normalizePhrase(phrase)
        guard !typed.isEmpty, !entries.isEmpty else { return false }
        return entries.allSatisfy { Mnemonic.normalizePhrase($0.mnemonic) == typed }
    }

    /// Lenient any-match sibling for NON-destructive ownership checks
    /// (forgot-PIN, honest-denial copy selection): true when `phrase` matches
    /// at least one readable stored mnemonic; unreadable entries are skipped
    /// (`persistedMnemonics()` semantics, errors logged there).
    nonisolated static func anyStoredMnemonicMatches(phrase: String) -> Bool {
        let typed = Mnemonic.normalizePhrase(phrase)
        guard !typed.isEmpty else { return false }
        return persistedMnemonics().contains { Mnemonic.normalizePhrase($0.mnemonic) == typed }
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
    /// triggers a clean rebuild via `stopAsync()` first.
    @discardableResult
    func start(network: Network) async throws -> (manager: PlatformWalletManager, wallet: ManagedPlatformWallet) {
        if let existingManager = manager,
           let existingWallet = wallet,
           runningNetwork == network {
            return (existingManager, existingWallet)
        }

        Self.logger.info("🪺 HOST :: starting for \(network.rawValue, privacy: .public)")
        DWLogger.log("HOST starting for \(network.rawValue)")

        let handles = try await buildRuntime(for: network)
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
                // The freshly built manager was never published — tear it
                // down deterministically instead of leaving it to the
                // deinit fallback.
                await handles.manager.shutdown()
                throw HostError.walletNotFound(network)
            }
            resolvedWallet = recovered
        } catch let error as HostError {
            await handles.manager.shutdown()
            throw error
        } catch {
            Self.logger.error("🪺 HOST :: wallet bootstrap failed: \(String(describing: error), privacy: .public)")
            await handles.manager.shutdown()
            throw HostError.walletBootstrapFailed(error)
        }

        publish(handles: handles, wallet: resolvedWallet)
        Self.logger.info("🪺 HOST :: stage 4/4 wallet restored for \(network.rawValue, privacy: .public)")
        Self.logger.info("🪺 HOST :: started for \(network.rawValue, privacy: .public)")
        DWLogger.log("HOST started for \(network.rawValue)")
        return (handles.manager, resolvedWallet)
    }

    /// Create or import a wallet as the SOLE active managed platform wallet.
    /// This is the fresh-install / recover path: it rebuilds the runtime from
    /// scratch (`buildRuntime` tears down any running manager), stores and
    /// verifies its mnemonic, creates the wallet, pins it active in the registry, and
    /// publishes it as bound. Onboarding's first wallet uses this and requests
    /// an explicit representation on every supported network. Legacy DashSync
    /// migration keeps the default network-scoped behavior so it can never
    /// manufacture cross-network copies while replaying old key material.
    ///
    /// For adding a wallet ALONGSIDE existing ones without rebinding the
    /// active wallet, use `addWallet(mnemonic:isImported:)` instead — this path replaces
    /// the running runtime and is not additive.
    @discardableResult
    func createOrImportWallet(
        mnemonic: String,
        network: Network,
        isImported: Bool,
        provisionAcrossSupportedNetworks: Bool = false
    ) async throws -> ManagedPlatformWallet {
        guard !mnemonic.isEmpty, Mnemonic.validate(mnemonic) else {
            throw HostError.invalidMnemonic
        }

        Self.logger.info("🪺 HOST :: creating managed wallet for \(network.rawValue, privacy: .public)")

        let handles = try await buildRuntime(for: network)
        let createdWallet: ManagedPlatformWallet
        do {
            createdWallet = try await createAndPersist(
                mnemonic: mnemonic,
                manager: handles.manager,
                network: handles.network,
                // Imported mnemonics may hold history from long before
                // this device: scan from the network's import floor
                // (genesis on testnet, block 200,000 on mainnet — see
                // `importedWalletBirthHeight`). Freshly generated
                // mnemonics keep nil — nothing can predate them, so
                // the scan anchors at the tip.
                birthHeight: isImported
                    ? Self.importedWalletBirthHeight(for: handles.network)
                    : nil,
                // Onboarding is not lifecycle-queue-serialized: keep the
                // persist→create critical section MainActor-atomic.
                offMainCreate: false)

            if provisionAcrossSupportedNetworks {
                let persistedWalletIds = Set(try WalletStorage().listWalletIdsWithMnemonic())
                let missingNetworks = try Self.missingWalletNetworks(
                    mnemonic: mnemonic,
                    persistedWalletIds: persistedWalletIds,
                    currentNetwork: network)

                for targetNetwork in missingNetworks where targetNetwork != network {
                    // Always temporary here: `buildRuntime` just cleared the
                    // published runtime, so `managerForStoredWalletOperation`
                    // can never hand back a live manager — but keep the
                    // guard so this call site stays correct if that changes.
                    let (targetManager, isTemporary) = try await managerForStoredWalletOperation(
                        network: targetNetwork)
                    do {
                        _ = try await createAndPersist(
                            mnemonic: mnemonic,
                            manager: targetManager,
                            network: targetNetwork,
                            birthHeight: isImported
                                ? Self.importedWalletBirthHeight(for: targetNetwork)
                                : nil,
                            offMainCreate: false)
                    } catch {
                        if isTemporary { await targetManager.shutdown() }
                        throw error
                    }
                    if isTemporary { await targetManager.shutdown() }
                    Self.logger.info(
                        "🪺 HOST :: provisioned onboarding wallet for \(targetNetwork.rawValue, privacy: .public)")
                }
            }
        } catch {
            // `createOrImportWallet` owns a freshly-built (not yet published)
            // runtime, so tear it down on failure — the manager was never
            // assigned to `self.manager`, so it must be shut down directly.
            // `createAndPersist` has already rolled back any provisional
            // mnemonic it wrote.
            await handles.manager.shutdown()
            throw error
        }

        if let kind = registryNetworkKind(for: network) {
            WalletEnvironment.setActiveWalletId(createdWallet.walletId, for: kind)
        }
        publish(handles: handles, wallet: createdWallet)

        let origin = isImported ? "imported" : "created"
        Self.logger.info("🪺 HOST :: \(origin, privacy: .public) managed wallet for \(network.rawValue, privacy: .public)")
        return createdWallet
    }

    /// Outcome of `addWallet(mnemonic:isImported:)`. `Sendable` because it
    /// crosses the lifecycle queue's awaitable seam
    /// (`SwiftDashSDKWalletRuntime.performAddWallet`).
    enum AddWalletResult: Sendable {
        /// The wallet was created and its mnemonic persisted; the running
        /// runtime is unchanged (the caller switches to it explicitly).
        case added(walletId: Data)
        /// A wallet deriving this walletId already has a persisted mnemonic on
        /// this device — nothing was written. The caller offers switching to it.
        case alreadyExists(walletId: Data)
    }

    /// Networks that still need a persisted representation for a logical
    /// wallet, ordered so the running network is created first. Keeping this
    /// decision pure makes the cross-network add behavior regression-testable
    /// without constructing SDK managers.
    nonisolated static func missingWalletNetworks(
        mnemonic: String,
        persistedWalletIds: Set<Data>,
        currentNetwork: Network
    ) throws -> [Network] {
        let otherNetwork: Network
        switch currentNetwork {
        case .mainnet:
            otherNetwork = .testnet
        case .testnet:
            otherNetwork = .mainnet
        default:
            throw HostError.unsupportedNetwork(currentNetwork)
        }

        let walletIds = try SwiftDashSDKStoredWalletNetworkResolver.walletIds(for: mnemonic)
        return [currentNetwork, otherNetwork].filter { network in
            guard let walletId = walletIds[network] else { return false }
            return !persistedWalletIds.contains(walletId)
        }
    }

    /// Add a wallet from `mnemonic` ADDITIVELY: create it in the already-running
    /// manager and persist its mnemonic, then materialize the same logical
    /// wallet for the other supported network. This is explicit provisioning
    /// at create/import time; reinstall recovery remains network-scoped and
    /// must never manufacture a mirror from an arbitrary surviving entry.
    /// Neither operation touches the active-wallet registries or rebinds the
    /// published active wallet. The caller (Wallets screen "Add Wallet")
    /// switches to the current-network wallet afterward via
    /// `SwiftDashSDKWalletRuntime.switchWallet`.
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
    ///
    /// Interactive callers route through
    /// `SwiftDashSDKWalletRuntime.performAddWallet`, which runs this method
    /// as one link of the serial lifecycle chain so queued refresh/reset
    /// operations cannot interleave with the multi-network provisioning.
    @discardableResult
    func addWallet(mnemonic: String, isImported: Bool) async throws -> AddWalletResult {
        let mnemonic = Mnemonic.normalizePhrase(mnemonic)
        guard !mnemonic.isEmpty, Mnemonic.validate(mnemonic) else {
            throw HostError.invalidMnemonic
        }
        guard let manager = manager,
              modelContainer != nil,
              let network = runningNetwork else {
            throw HostError.walletNotFound(runningNetwork ?? .mainnet)
        }

        let walletIds = try SwiftDashSDKStoredWalletNetworkResolver.walletIds(for: mnemonic)
        guard let currentWalletId = walletIds[network] else {
            throw HostError.unsupportedNetwork(network)
        }

        let persistedWalletIds = Set(try WalletStorage().listWalletIdsWithMnemonic())
        let networksToCreate = try Self.missingWalletNetworks(
            mnemonic: mnemonic,
            persistedWalletIds: persistedWalletIds,
            currentNetwork: network)
        let createsCurrentNetwork = networksToCreate.contains(network)

        for targetNetwork in networksToCreate {
            let targetManager: PlatformWalletManager
            let isTemporary: Bool
            if targetNetwork == network {
                targetManager = manager
                isTemporary = false
            } else {
                // Wall-clock only (this line always runs on the MainActor);
                // per-stage thread attribution lives in the stage 1-4 logs.
                let prepStarted = CFAbsoluteTimeGetCurrent()
                (targetManager, isTemporary) = try await managerForStoredWalletOperation(
                    network: targetNetwork)
                let prepMs = Int((CFAbsoluteTimeGetCurrent() - prepStarted) * 1000)
                DWLogger.log("HOST mirror-prep for \(targetNetwork.rawValue) total \(prepMs)ms")
            }
            do {
                _ = try await createAndPersist(
                    mnemonic: mnemonic,
                    manager: targetManager,
                    network: targetNetwork,
                    // Same semantics as `createOrImportWallet`: imports scan
                    // from each network's import floor, freshly generated
                    // wallets from that network's tip.
                    birthHeight: isImported
                        ? Self.importedWalletBirthHeight(for: targetNetwork)
                        : nil,
                    // The interactive add runs as one lifecycle-queue op
                    // (`performAddWallet`), so refreshes cannot observe the
                    // suspension the off-main create introduces.
                    offMainCreate: true)
            } catch {
                if isTemporary { await targetManager.shutdown() }
                throw error
            }
            if isTemporary { await targetManager.shutdown() }
            Self.logger.info(
                "🪺 HOST :: added managed wallet for \(targetNetwork.rawValue, privacy: .public) (additive)")
        }

        if createsCurrentNetwork {
            return .added(walletId: currentWalletId)
        }

        Self.logger.info("🪺 HOST :: current-network walletId already persisted; missing mirror repaired if needed")
        return .alreadyExists(walletId: currentWalletId)
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
    /// `offMainCreate` picks the SDK create overload. `true` (interactive
    /// add): the async overload — the blocking FFI leaves the MainActor,
    /// but the transaction gains a REAL suspension point between the
    /// mnemonic persist and the wallet rows appearing; safe only when the
    /// caller is serialized against runtime refreshes (the add flow runs on
    /// the lifecycle queue). `false` (onboarding/migration): the sync
    /// overload — no suspension between persist and create, so a
    /// concurrently scheduled `startIfReady`/refresh can never observe the
    /// half-state (mnemonic present, no wallet rows) and build a competing
    /// runtime; `createOrImportWallet` is NOT queue-serialized (the
    /// migrator is awaited by refresh itself — enqueueing would deadlock),
    /// so it must keep the MainActor-atomic critical section.
    private func createAndPersist(
        mnemonic: String,
        manager: PlatformWalletManager,
        network: Network,
        birthHeight: UInt32?,
        offMainCreate: Bool
    ) async throws -> ManagedPlatformWallet {
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
            return try await MnemonicFirstWalletCreation.run(
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
                    if offMainCreate {
                        // Async SDK overload: the blocking native create
                        // runs on the SDK's dedicated queue, not the main
                        // thread.
                        return try await manager.createWallet(
                            mnemonic: mnemonic,
                            network: network,
                            name: "dashwallet",
                            createDefaultAccounts: true,
                            birthHeight: birthHeight)
                    }
                    // Sync SDK overload, forced by the explicit non-async
                    // function type (an async context would otherwise
                    // prefer the async one): blocks the MainActor for the
                    // whole create, keeping persist→create atomic for the
                    // unserialized onboarding path.
                    let syncCreate: () throws -> ManagedPlatformWallet = {
                        try manager.createWallet(
                            mnemonic: mnemonic,
                            network: network,
                            name: "dashwallet",
                            createDefaultAccounts: true,
                            birthHeight: birthHeight)
                    }
                    return try syncCreate()
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

    /// Tear down the host's active references, running the manager's blocking
    /// native teardown OFF the main thread and returning only when it has
    /// completed (`nil` when no manager was running). The per-network
    /// `ModelContainer` remains process-cached so a later runtime rebuild does
    /// not open a second container over the same SQLite store.
    ///
    /// Order matters:
    /// 1. `contactCryptoDrainWatch` is cancelled AND awaited first — the task
    ///    holds the manager strongly and calls `unlockWalletFromKeychain`
    ///    (FFI), so it must be provably finished before the manager's handle
    ///    is taken. No self-deadlock: this method and the task share the
    ///    main actor, but `await value` suspends (freeing the actor) and the
    ///    task's `for await …values` / `Task.sleep` both honor cancellation,
    ///    so the wait is short and deterministic.
    /// 2. `manager.shutdown()` takes the FFI handle exactly once and runs the
    ///    five sync stops + destroy on the SDK's dedicated destroy queue.
    /// 3. Only then are the host references dropped — their deinits find a
    ///    NULL handle and do no FFI.
    ///
    /// Persisted-row cleanup on wipe is owned by `PlatformAddressSyncCoordinator`
    /// — it must happen BEFORE BLAST's tokio task winds down so in-flight
    /// `walletNetwork(walletId:)` callbacks early-exit on an empty fetch.
    /// The host is torn down last (after BLAST + SPV stops), so the
    /// invariant doesn't hold here.
    @discardableResult
    func stopAsync() async -> PlatformWalletShutdownMetrics? {
        let drainWatch = contactCryptoDrainWatch
        contactCryptoDrainWatch = nil
        drainWatch?.cancel()
        await drainWatch?.value

        let metrics = await manager?.shutdown()
        if let metrics {
            let stepSummary = metrics.steps
                .map { "\($0.name)=\($0.milliseconds)ms(code \($0.ffiCode))" }
                .joined(separator: " ")
            // DWLogger on purpose (os_log doesn't reach diagnostic exports):
            // this line is the field telemetry for how often the native
            // teardown hits its wedged-pass worst case.
            DWLogger.log(
                "HOST shutdown: total=\(metrics.totalMilliseconds)ms offMain=\(metrics.ranOffMainThread) \(stepSummary)")
        }

        clearRuntimeReferences()
        return metrics
    }

    /// Drop the host's references AFTER the manager teardown has completed.
    /// Split out of `stopAsync` so the shutdown-first ordering is the only
    /// public shape; never call this with a still-configured manager.
    private func clearRuntimeReferences() {
        manager = nil
        wallet = nil
        sdk = nil
        modelContainer = nil
        runningNetwork = nil

        Self.logger.info("🪺 HOST :: stopped")
        DWLogger.log("HOST stopped")
    }

    // MARK: - Runtime bootstrap

    private func buildRuntime(for network: Network) async throws -> RuntimeHandles {
        if manager != nil {
            await stopAsync()
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
            // Timed because it is main-thread work: SDK creation prefetches
            // quorums over the network (~1-2s observed). Known stage-1
            // limitation — the switch overlay covers it; the measurement is
            // the data for deciding whether to move it off-main later.
            let started = CFAbsoluteTimeGetCurrent()
            newSDK = try SDK(network: network, platformVersion: platformVersion)
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            Self.logger.info(
                "🪺 HOST :: stage 1/4 SDK created for \(network.rawValue, privacy: .public), protocol \(platformVersion == 0 ? "auto-detect" : "pinned v\(platformVersion)", privacy: .public)")
            DWLogger.log("HOST stage 1/4 SDK created for \(network.rawValue) in \(ms)ms")
        } catch {
            Self.logger.error("🪺 HOST :: SDK init failed: \(String(describing: error), privacy: .public)")
            throw HostError.sdkInitFailed(error)
        }

        let container: ModelContainer
        do {
            Self.logger.info("🪺 HOST :: stage 2/4 obtaining ModelContainer for \(network.rawValue, privacy: .public)")
            // Timed for the same reason as stage 1: main-thread work whose
            // real cost decides whether it ever needs to move off-main. The
            // cached (reused) path should be ~0ms; only the first build of a
            // network's container in the process pays the store-open cost.
            let started = CFAbsoluteTimeGetCurrent()
            let cached = try modelContainerCache.value(for: network.networkName) {
                try buildModelContainer(for: network)
            }
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            container = cached.value
            Self.logger.info("🪺 HOST :: stage 2/4 ModelContainer \(cached.reused ? "reused" : "created", privacy: .public) for \(network.rawValue, privacy: .public)")
            DWLogger.log("HOST stage 2/4 ModelContainer \(cached.reused ? "reused" : "created") for \(network.rawValue) in \(ms)ms")
        } catch {
            Self.logger.error("🪺 HOST :: ModelContainer build failed: \(String(describing: error), privacy: .public)")
            throw HostError.modelContainerFailed(error)
        }

        let newManager = PlatformWalletManager()
        do {
            Self.logger.info("🪺 HOST :: stage 3/4 configuring manager for \(network.rawValue, privacy: .public)")
            let started = CFAbsoluteTimeGetCurrent()
            try newManager.configure(sdk: newSDK, modelContainer: container)
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            Self.logger.info("🪺 HOST :: stage 3/4 manager configured for \(network.rawValue, privacy: .public)")
            DWLogger.log("HOST stage 3/4 manager configured for \(network.rawValue) in \(ms)ms")
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
    /// The live manager is reused for its network (`isTemporary == false` —
    /// the caller must NOT shut it down). The other network gets a detached
    /// manager over the process-cached `ModelContainer`
    /// (`isTemporary == true` — the caller owns its lifecycle and must
    /// `await manager.shutdown()` when done), avoiding a second open of the
    /// same SQLite store and leaving the published runtime unchanged until
    /// the wipe commits.
    func managerForWipe(network: Network) async throws -> (manager: PlatformWalletManager, isTemporary: Bool) {
        try await managerForStoredWalletOperation(network: network)
    }

    /// Returns a manager over the network's persisted store without changing
    /// the published runtime. Shared by full-device wipe and explicit
    /// cross-network wallet provisioning. `isTemporary` tells the caller
    /// whether it owns the manager's teardown (`await manager.shutdown()`
    /// after use) or borrowed the live published one (hands off).
    private func managerForStoredWalletOperation(
        network: Network
    ) async throws -> (manager: PlatformWalletManager, isTemporary: Bool) {
        if runningNetwork == network, let manager {
            return (manager, false)
        }

        let handles = try makeRuntime(for: network)
        do {
            // Stage 4 of the detached-manager bootstrap: cost scales with the
            // number of persisted wallets on `network` (bulk FFI + per-wallet
            // FFI + keychain unlock), all currently on the main thread.
            let started = CFAbsoluteTimeGetCurrent()
            let restored = try handles.manager.loadFromPersistor()
            let ms = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            DWLogger.log("HOST stage 4/4 loadFromPersistor for \(network.rawValue) restored=\(restored.count) in \(ms)ms")
        } catch {
            // The detached manager is already fully configured; rethrowing
            // without an explicit shutdown would leave its native teardown to
            // the fire-and-forget deinit fallback, racing a follow-up rebuild
            // over the same process-cached ModelContainer — exactly what the
            // isTemporary ownership contract exists to prevent.
            await handles.manager.shutdown()
            throw error
        }
        return (handles.manager, true)
    }

    private func loadPersistedWallet(
        manager: PlatformWalletManager,
        network: Network
    ) throws -> ManagedPlatformWallet {
        let loadStarted = CFAbsoluteTimeGetCurrent()
        let restored = try manager.loadFromPersistor()
        let loadMs = Int((CFAbsoluteTimeGetCurrent() - loadStarted) * 1000)
        DWLogger.log("HOST stage 4/4 loadFromPersistor for \(network.rawValue) restored=\(restored.count) in \(loadMs)ms")
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
    /// so a re-run after a partial failure converges. Network-scoped ids are
    /// never replayed through the other network's manager.
    /// Wipe race note: the wiper deletes mnemonics before `handleWalletWiped`,
    /// so a refresh racing a wipe finds an empty list here and fails the start
    /// — and the next refresh's `hasSDKWallet` gate stays closed.
    private func recoverPersistedWallet(handles: RuntimeHandles) -> ManagedPlatformWallet? {
        let inventory = Self.persistedMnemonics()
        let entries = Self.recoverablePersistedMnemonics(
            inventory,
            for: handles.network)
        guard !entries.isEmpty else { return nil }

        for entry in entries {
            do {
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
                    try? handles.manager.deleteWallet(walletId: created.walletId)
                    Self.logger.error("🪺 HOST :: recovered wallet id did not match its network-scoped Keychain id; discarded created wallet")
                }
            } catch {
                Self.logger.error("🪺 HOST :: keychain wallet recovery failed for one entry: \(String(describing: error), privacy: .public)")
            }
        }

        guard let resolved = resolveActiveWallet(in: handles.manager, network: handles.network) else { return nil }
        Self.logger.info("🪺 HOST :: recovered persisted wallet from keychain mnemonic(s); network=\(handles.network.networkName, privacy: .public) eligible=\(entries.count, privacy: .public) skipped=\(inventory.count - entries.count, privacy: .public)")
        return resolved
    }

    private func publish(handles: RuntimeHandles, wallet resolvedWallet: ManagedPlatformWallet) {
        sdk = handles.sdk
        manager = handles.manager
        wallet = resolvedWallet
        modelContainer = handles.modelContainer
        runningNetwork = handles.network
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
