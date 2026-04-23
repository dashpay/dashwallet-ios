//
//  PlatformAddressSyncCoordinator.swift
//  DashWallet
//
//  Drives the SwiftDashSDK Platform L2 address sync (BLAST). Despite
//  the name collision with the old `SwiftDashSDKSPVCoordinator`, this is
//  a completely different pipeline: it polls DAPI over HTTP/gRPC for
//  Platform-layer address balances, does **not** do P2P chain sync, and
//  uses the Platform chain tip (hundreds of thousands of blocks), not
//  the L1 core chain tip (millions).
//
//  Pipeline shape — see `PlatformBalanceSyncService.swift` in the
//  SwiftExampleApp for the reference implementation this mirrors:
//
//   1. `SDK.initialize()` once per process.
//   2. `SDK(network:)` per network.
//   3. `ModelContainer` over `DashModelContainer.modelTypes`, one sqlite
//      file per network under Documents/SwiftDashSDK/Platform/<network>/.
//   4. `PlatformWalletManager.configure(sdk:, modelContainer:)`.
//   5. `loadFromPersistor()` — reuse if non-empty. Otherwise pull the
//      app mnemonic from `WalletStorage().retrieveMnemonic()` and
//      `createWallet(mnemonic:, network:, name: "dashwallet")`.
//   6. `startPlatformAddressSync()` — spawns the tokio loop.
//   7. Subscribe to `manager.$lastPlatformAddressSyncEvent` on main,
//      filter by our wallet id, accumulate counters, compute balance
//      snapshot from `ManagedPlatformAddressWallet.addressesWithBalances()`.
//

import Combine
import Foundation
import OSLog
import SwiftData
import SwiftDashSDK

@MainActor
@objc(DWPlatformAddressSyncCoordinator)
public final class PlatformAddressSyncCoordinator: NSObject, ObservableObject {

    // MARK: - Singleton

    public static let shared = PlatformAddressSyncCoordinator()

    // MARK: - Logging

    fileprivate static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.platform-address-sync-coordinator")

    // MARK: - Published state

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var runningNetwork: AppNetwork? = nil

    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncTime: Date? = nil
    @Published public private(set) var lastError: String? = nil

    @Published public private(set) var platformBalance: UInt64 = 0
    @Published public private(set) var activeAddressCount: Int = 0
    @Published public private(set) var derivedAddresses: [DerivedPlatformAddress] = []

    @Published public private(set) var checkpointHeight: UInt64 = 0
    @Published public private(set) var chainTipHeight: UInt64 = 0
    @Published public private(set) var lastSyncHeight: UInt64 = 0
    @Published public private(set) var lastKnownRecentBlock: UInt64 = 0
    @Published public private(set) var lastSyncBlockTime: Date? = nil

    @Published public private(set) var syncCountSinceLaunch: Int = 0
    @Published public private(set) var totalTrunkQueries: UInt32 = 0
    @Published public private(set) var totalBranchQueries: UInt32 = 0
    @Published public private(set) var totalCompactedQueries: UInt32 = 0
    @Published public private(set) var totalRecentQueries: UInt32 = 0
    @Published public private(set) var totalRecentEntries: UInt32 = 0
    @Published public private(set) var totalCompactedEntries: UInt32 = 0

    // MARK: - Main-actor-owned state

    private var sdk: SDK?
    private var walletManager: PlatformWalletManager?
    private var wallet: ManagedPlatformWallet?
    private var platformAddressWallet: ManagedPlatformAddressWallet?
    private var modelContainer: ModelContainer?

    public var swiftDataContainer: ModelContainer? { modelContainer }

    private var syncEventCancellable: AnyCancellable?
    private var syncStateCancellable: AnyCancellable?

    // MARK: - Process-wide SDK init guard

    private static var sdkInitialized = false
    private static let sdkInitLock = NSLock()

    private static func ensureSDKInitialized() {
        sdkInitLock.lock()
        defer { sdkInitLock.unlock() }
        if !sdkInitialized {
            SDK.initialize()
            sdkInitialized = true
        }
    }

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Public lifecycle (Obj-C bridge)

    @objc(startForCurrentNetwork)
    public nonisolated static func startForCurrentNetwork() {
        Task { @MainActor in
            await shared.startForCurrentNetworkMainActor()
        }
    }

    @objc(stop)
    public nonisolated static func stop() {
        Task { @MainActor in
            await shared.performStop()
        }
    }

    // MARK: - Public lifecycle (Swift)

    public nonisolated func start(for network: AppNetwork) {
        Task { @MainActor in
            await self.performStart(network: network)
        }
    }

    public nonisolated func stop() {
        Task { @MainActor in
            await self.performStop()
        }
    }

    public func syncNow() async {
        guard !isSyncing else { return }
        guard let manager = walletManager else {
            lastError = "Platform wallet not configured"
            return
        }
        isSyncing = true
        lastError = nil
        do {
            try await manager.syncPlatformAddressNow()
        } catch {
            isSyncing = false
            lastError = error.localizedDescription
            Self.logger.error("🛰️ PLATFORM-ADDR :: syncPlatformAddressNow threw: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Transfer

    /// Signs and submits a Platform credit transfer from the highest-balance
    /// derived address with `balance >= amount` to `destination`. Platform's
    /// state transition protocol enforces `sum(inputs) == sum(outputs)`, so
    /// we transfer exactly `amount` — any unspent balance stays on the source
    /// address. `feeFromInputIndex: 0` designates which input's account bears
    /// the processing fee, charged separately by Platform.
    public func transfer(
        destination: String,
        amount: UInt64
    ) async throws -> PlatformAddressInfosResult {
        guard isRunning,
              let sdk = sdk,
              let walletId = wallet?.walletId,
              let container = modelContainer,
              let network = runningNetwork
        else { throw SendError.coordinatorNotReady }

        let descriptor = FetchDescriptor<PersistentPlatformAddress>(
            predicate: #Predicate<PersistentPlatformAddress> {
                $0.walletId == walletId && $0.balance >= amount
            })
        let rows = try container.mainContext.fetch(descriptor)
        guard let source = rows.max(by: { $0.balance < $1.balance })
        else { throw SendError.noFundedAddress }

        guard let destBytes = Self.platformAddressBytes(bech32m: destination)
        else { throw SendError.invalidDestination }

        var srcBytes = Data([source.addressType])
        srcBytes.append(source.addressHash)

        guard let mnemonic = SwiftDashSDKMnemonicReader.readMnemonic()
        else { throw SendError.mnemonicUnavailable }

        let keyWallet = try Wallet(
            mnemonic: mnemonic,
            network: keyWalletNetwork(for: network))
        let wif = try keyWallet.derivePrivateKey(path: source.derivationPath)
        let parsed = PrivateKeyParser.parseWIF(wif)
        guard let rawKey = parsed.data, rawKey.count == 32
        else { throw SendError.keyDecodeFailed(parsed.error ?? "invalid WIF") }

        let input = Addresses.AddressTransferInput(
            addressBytes: srcBytes,
            amount: amount,
            nonce: source.nonce,
            privateKey: rawKey)
        let output = Addresses.AddressTransferOutput(
            addressBytes: destBytes,
            amount: amount)

        Self.logger.info(
            "🛰️ PLATFORM-SEND :: from \(source.address, privacy: .public) → \(destination, privacy: .public) :: amount=\(amount) sourceBalance=\(source.balance) nonce=\(source.nonce)")

        let result = try sdk.addresses.transferFunds(
            inputs: [input],
            outputs: [output],
            feeFromInputIndex: 0)

        Task { await self.syncNow() }
        return result
    }

    /// Clear the UI counters/display without tearing down the sync loop.
    public func clearDisplay() {
        platformBalance = 0
        activeAddressCount = 0
        derivedAddresses = []
        checkpointHeight = 0
        chainTipHeight = 0
        lastSyncHeight = 0
        lastKnownRecentBlock = 0
        lastSyncBlockTime = nil
        lastSyncTime = nil
        lastError = nil
        syncCountSinceLaunch = 0
        totalTrunkQueries = 0
        totalBranchQueries = 0
        totalCompactedQueries = 0
        totalRecentQueries = 0
        totalRecentEntries = 0
        totalCompactedEntries = 0
    }

    // MARK: - Main-actor work

    private func startForCurrentNetworkMainActor() async {
        guard let network = resolveCurrentAppNetwork() else {
            Self.logger.info("🛰️ PLATFORM-ADDR :: skipping start — unsupported network")
            return
        }
        await performStart(network: network)
    }

    private func performStart(network: AppNetwork) async {
        if isRunning && runningNetwork == network {
            Self.logger.info("🛰️ PLATFORM-ADDR :: start ignored — already running on \(network.rawValue, privacy: .public)")
            return
        }

        if walletManager != nil {
            await performStop()
        }

        guard let platformNetwork = platformNetwork(for: network) else {
            Self.logger.error("🛰️ PLATFORM-ADDR :: \(network.rawValue, privacy: .public) is not a supported PlatformNetwork")
            lastError = "Platform SDK does not support \(network.rawValue)"
            return
        }

        Self.ensureSDKInitialized()
        Self.logger.info("🛰️ PLATFORM-ADDR :: starting for \(network.rawValue, privacy: .public)")

        let newSDK: SDK
        do {
            newSDK = try SDK(network: network.sdkNetwork)
        } catch {
            Self.logger.error("🛰️ PLATFORM-ADDR :: SDK init failed: \(String(describing: error), privacy: .public)")
            lastError = "SDK init failed: \(error.localizedDescription)"
            return
        }

        let container: ModelContainer
        do {
            container = try buildModelContainer(for: network)
        } catch {
            Self.logger.error("🛰️ PLATFORM-ADDR :: ModelContainer build failed: \(String(describing: error), privacy: .public)")
            lastError = "ModelContainer setup failed: \(error.localizedDescription)"
            return
        }

        let manager = PlatformWalletManager()
        do {
            try manager.configure(sdk: newSDK, modelContainer: container)
        } catch {
            Self.logger.error("🛰️ PLATFORM-ADDR :: configure failed: \(String(describing: error), privacy: .public)")
            lastError = "PlatformWalletManager configure failed: \(error.localizedDescription)"
            return
        }

        let resolvedWallet: ManagedPlatformWallet
        do {
            resolvedWallet = try bootstrapWallet(manager: manager, network: platformNetwork)
        } catch {
            Self.logger.error("🛰️ PLATFORM-ADDR :: wallet bootstrap failed: \(String(describing: error), privacy: .public)")
            lastError = "Wallet bootstrap failed: \(error.localizedDescription)"
            return
        }

        let addressWallet: ManagedPlatformAddressWallet
        do {
            addressWallet = try resolvedWallet.platformAddressWallet()
        } catch {
            Self.logger.error("🛰️ PLATFORM-ADDR :: platformAddressWallet() failed: \(String(describing: error), privacy: .public)")
            lastError = "platformAddressWallet failed: \(error.localizedDescription)"
            return
        }

        // Seed from persisted state before kicking the sync loop, so the UI has
        // something to show immediately on relaunch.
        seedFromPersistedState(manager: manager, walletId: resolvedWallet.walletId)

        do {
            if try !manager.isPlatformAddressSyncRunning() {
                try manager.startPlatformAddressSync()
            }
        } catch {
            Self.logger.error("🛰️ PLATFORM-ADDR :: startPlatformAddressSync failed: \(String(describing: error), privacy: .public)")
            lastError = "startPlatformAddressSync failed: \(error.localizedDescription)"
            return
        }

        self.sdk = newSDK
        self.modelContainer = container
        self.walletManager = manager
        self.wallet = resolvedWallet
        self.platformAddressWallet = addressWallet
        self.runningNetwork = network
        self.isRunning = true
        self.lastError = nil

        subscribeToManager(manager: manager, walletId: resolvedWallet.walletId)
        refreshDerivedAddresses()

        Self.logger.info("🛰️ PLATFORM-ADDR :: started for \(network.rawValue, privacy: .public)")
    }

    private func performStop() async {
        // Mirror SwiftExampleApp's delete-wallet sequence
        // (`WalletDetailView.deleteWallet()` + `rebindWalletScopedServices()`):
        //
        //   1. Delete the `PersistentWallet` row from SwiftData FIRST. After
        //      this, any in-flight BLAST callback that does
        //      `walletNetwork(walletId:)` gets an empty fetch and early-exits,
        //      instead of traversing deeper and hitting refs that will be
        //      dropped by the teardown below.
        //   2. Cancel Combine subscriptions.
        //   3. `stopPlatformAddressSync()` on the still-alive manager.
        //   4. Drop Swift-side handles. `modelContainer` stays alive through
        //      the reset — the next `performStart` overwrites it, and keeping
        //      it referenced here means SwiftData contexts captured by
        //      Rust-side persister closures don't dangle while tokio winds down.
        deletePersistedWalletIfAny()

        syncEventCancellable?.cancel()
        syncEventCancellable = nil
        syncStateCancellable?.cancel()
        syncStateCancellable = nil

        if let manager = walletManager {
            do {
                if try manager.isPlatformAddressSyncRunning() {
                    try manager.stopPlatformAddressSync()
                }
                Self.logger.info("🛰️ PLATFORM-ADDR :: stopped")
            } catch {
                Self.logger.error("🛰️ PLATFORM-ADDR :: stopPlatformAddressSync threw: \(String(describing: error), privacy: .public)")
            }
        }

        walletManager = nil
        wallet = nil
        platformAddressWallet = nil
        sdk = nil
        runningNetwork = nil
        isRunning = false
        clearDisplay()
    }

    private func deletePersistedWalletIfAny() {
        guard let container = modelContainer, let walletId = wallet?.walletId else {
            return
        }
        let descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate<PersistentWallet> { $0.walletId == walletId })
        do {
            let rows = try container.mainContext.fetch(descriptor)
            for row in rows {
                container.mainContext.delete(row)
            }
            try container.mainContext.save()
            Self.logger.info(
                "🛰️ PLATFORM-ADDR :: deleted \(rows.count) PersistentWallet row(s) before stop")
        } catch {
            Self.logger.error(
                "🛰️ PLATFORM-ADDR :: PersistentWallet cleanup threw: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Wallet bootstrap

    private func bootstrapWallet(
        manager: PlatformWalletManager,
        network: PlatformNetwork
    ) throws -> ManagedPlatformWallet {
        let restored = try manager.loadFromPersistor()
        if let first = restored.first {
            Self.logger.info("🛰️ PLATFORM-ADDR :: reusing persisted wallet")
            return first
        }
        if let existing = manager.firstWallet {
            return existing
        }

        let storage = WalletStorage()
        let mnemonic = try storage.retrieveMnemonic()
        Self.logger.info("🛰️ PLATFORM-ADDR :: creating new platform wallet from existing mnemonic")
        return try manager.createWallet(
            mnemonic: mnemonic,
            network: network,
            name: "dashwallet",
            createDefaultAccounts: true)
    }

    // MARK: - Combine subscriptions

    private func subscribeToManager(manager: PlatformWalletManager, walletId: Data) {
        syncStateCancellable = manager.$platformAddressSyncIsSyncing
            .receive(on: RunLoop.main)
            .sink { [weak self] syncing in
                self?.isSyncing = syncing
            }

        syncEventCancellable = manager.$lastPlatformAddressSyncEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self, let event else { return }
                self.handleSyncEvent(event, walletId: walletId)
            }
    }

    private func handleSyncEvent(_ event: PlatformAddressSyncEvent, walletId: Data) {
        guard let result = event.result(for: walletId) else { return }

        if result.success {
            lastError = nil
            if result.checkpointHeight > 0 {
                checkpointHeight = result.checkpointHeight
            }
            if result.newSyncHeight > chainTipHeight {
                chainTipHeight = result.newSyncHeight
            }
            lastSyncHeight = result.newSyncHeight
            lastKnownRecentBlock = result.lastKnownRecentBlock
            if result.newSyncTimestamp > 0 {
                lastSyncBlockTime = Date(timeIntervalSince1970: TimeInterval(result.newSyncTimestamp))
            }

            totalTrunkQueries += result.metrics.trunkQueries
            totalBranchQueries += result.metrics.branchQueries
            totalCompactedQueries += result.metrics.compactedQueries
            totalRecentQueries += result.metrics.recentQueries
            totalRecentEntries += result.metrics.recentEntriesReturned
            totalCompactedEntries += result.metrics.compactedEntriesReturned

            lastSyncTime = Date(timeIntervalSince1970: TimeInterval(event.syncUnixSeconds))
            syncCountSinceLaunch += 1

            Task { [weak self] in
                await self?.refreshBalanceSnapshot()
            }
        } else {
            lastError = result.errorMessage ?? "Platform address sync failed"
        }
    }

    private func refreshBalanceSnapshot() async {
        // Source of truth is SwiftData — the FFI `addressesWithBalances()` /
        // `totalCredits()` pair lags behind the BLAST persistence callbacks
        // and can report zero while the DB already holds the funded rows.
        refreshDerivedAddresses()
    }

    private func refreshDerivedAddresses() {
        guard
            let container = modelContainer,
            let walletId = wallet?.walletId
        else {
            derivedAddresses = []
            platformBalance = 0
            activeAddressCount = 0
            return
        }

        let descriptor = FetchDescriptor<PersistentPlatformAddress>(
            predicate: #Predicate<PersistentPlatformAddress> { $0.walletId == walletId },
            sortBy: [
                SortDescriptor(\.accountIndex),
                SortDescriptor(\.addressIndex),
            ])

        do {
            let rows = try container.mainContext.fetch(descriptor)
            derivedAddresses = rows.map { row in
                DerivedPlatformAddress(
                    address: row.address,
                    accountIndex: row.accountIndex,
                    addressIndex: row.addressIndex,
                    isUsed: row.isUsed,
                    balance: row.balance)
            }
            platformBalance = rows.reduce(0) { $0 + $1.balance }
            activeAddressCount = rows.reduce(0) { $1.balance > 0 ? $0 + 1 : $0 }
        } catch {
            Self.logger.warning("🛰️ PLATFORM-ADDR :: derived-address fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Seed from persistence

    private func seedFromPersistedState(manager: PlatformWalletManager, walletId: Data) {
        guard let handler = manager.persistence else { return }

        let cached = handler.loadCachedBalances(walletId: walletId)
        if !cached.isEmpty {
            var total: UInt64 = 0
            var nonZero = 0
            for (_, _, balance, _, _, _) in cached {
                total += balance
                if balance > 0 { nonZero += 1 }
            }
            platformBalance = total
            activeAddressCount = nonZero
        }

        if let state = handler.loadCachedSyncState(walletId: walletId) {
            chainTipHeight = state.syncHeight
            lastSyncHeight = state.syncHeight
            if state.syncTimestamp > 0 {
                lastSyncBlockTime = Date(timeIntervalSince1970: TimeInterval(state.syncTimestamp))
            }
            lastKnownRecentBlock = state.lastKnownRecentBlock
        }
    }

    // MARK: - Helpers

    private func resolveCurrentAppNetwork() -> AppNetwork? {
        let chain = DWEnvironment.sharedInstance().currentChain
        if chain.isMainnet() { return .mainnet }
        if chain.isTestnet() { return .testnet }
        return nil
    }

    private func platformNetwork(for network: AppNetwork) -> PlatformNetwork? {
        switch network {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        case .regtest: return nil
        }
    }

    private func keyWalletNetwork(for network: AppNetwork) -> KeyWalletNetwork {
        switch network {
        case .mainnet: return .mainnet
        case .testnet: return .testnet
        case .devnet: return .devnet
        case .regtest: return .regtest
        }
    }

    /// Translate a DIP-0018 bech32m address (HRP `dash`/`tdash`, what dashwallet's
    /// Receive screen emits) into the 21-byte `[variant | hash]` form the SDK's
    /// `transferFunds` expects. Version byte → variant: `0xb0` → 0 (P2PKH),
    /// `0x80` → 1 (P2SH).
    static func platformAddressBytes(bech32m: String) -> Data? {
        guard let decoded = Bech32m.decode(bech32m.lowercased()),
              decoded.hrp == "dash" || decoded.hrp == "tdash",
              decoded.data.count == 21
        else { return nil }

        let variant: UInt8
        switch decoded.data[0] {
        case 0xb0: variant = 0
        case 0x80: variant = 1
        default: return nil
        }
        var bytes = Data([variant])
        bytes.append(decoded.data.subdata(in: 1..<21))
        return bytes
    }

    private func buildModelContainer(for network: AppNetwork) throws -> ModelContainer {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        let dir = documents
            .appendingPathComponent("SwiftDashSDK", isDirectory: true)
            .appendingPathComponent("Platform", isDirectory: true)
            .appendingPathComponent(network.rawValue, isDirectory: true)
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

// MARK: - DerivedPlatformAddress

public struct DerivedPlatformAddress: Identifiable, Equatable, Sendable {
    public let address: String
    public let accountIndex: UInt32
    public let addressIndex: UInt32
    public let isUsed: Bool
    public let balance: UInt64

    public var id: String { address }
}

// MARK: - SendError

extension PlatformAddressSyncCoordinator {
    public enum SendError: LocalizedError {
        case coordinatorNotReady
        case noFundedAddress
        case invalidDestination
        case mnemonicUnavailable
        case keyDecodeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .coordinatorNotReady:
                return NSLocalizedString(
                    "Platform sync is not running. Open Tools → Platform Sync Status to start it.",
                    comment: "")
            case .noFundedAddress:
                return NSLocalizedString(
                    "No funded Platform address has enough balance to cover this amount plus fees.",
                    comment: "")
            case .invalidDestination:
                return NSLocalizedString(
                    "Destination address is not a valid Platform bech32m address.",
                    comment: "")
            case .mnemonicUnavailable:
                return NSLocalizedString(
                    "Wallet mnemonic is unavailable. Unlock the wallet and try again.",
                    comment: "")
            case .keyDecodeFailed(let reason):
                return String(
                    format: NSLocalizedString("Private key could not be decoded: %@", comment: ""),
                    reason)
            }
        }
    }
}
