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
//   5. `SwiftDashSDKHost.start(network:)` loads the persisted
//      `ManagedPlatformWallet`; create/import paths go through the host before
//      BLAST starts.
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
    @Published public private(set) var runningNetwork: Network? = nil

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
            await shared.performStop(deletingPersistedWallet: false)
        }
    }

    /// Wipe-path entry: delete the `PersistentWallet` row from SwiftData BEFORE
    /// stopping the BLAST tokio task, so in-flight `walletNetwork(walletId:)`
    /// callbacks early-exit instead of racing the teardown. Mirrors
    /// `WalletDetailView.deleteWallet()` + `rebindWalletScopedServices()` in
    /// SwiftExampleApp. Must only be called when the wallet is actually being
    /// wiped — a plain stop/restart should use `stop()` to preserve address +
    /// balance history.
    @objc(stopForWipe)
    public nonisolated static func stopForWipe() {
        Task { @MainActor in
            await shared.performStop(deletingPersistedWallet: true)
        }
    }

    // MARK: - Public lifecycle (Swift)

    public nonisolated func start(for network: Network) {
        Task { @MainActor in
            await self.performStart(network: network)
        }
    }

    public nonisolated func stop() {
        Task { @MainActor in
            await self.performStop(deletingPersistedWallet: false)
        }
    }

    // MARK: - Public lifecycle (async)
    //
    // Used by `SwiftDashSDKWalletRuntime`'s single async lifecycle pipeline.
    // The nonisolated/objc wrappers above stay for fire-and-forget callers.

    @MainActor
    public func startAsync(for network: Network) async throws {
        await performStart(network: network)
        if isRunning && runningNetwork == network {
            return
        }
        throw StartError.failed(lastError ?? "BLAST start failed")
    }

    @MainActor
    public func stopAsync() async {
        await performStop(deletingPersistedWallet: false)
    }

    @MainActor
    public static func stopForWipeAsync() async {
        await shared.performStop(deletingPersistedWallet: true)
    }

    enum StartError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return "BLAST start failed: \(message)"
            }
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

    /// Submits a Platform credit transfer to `destination`. Inputs are
    /// auto-selected largest-first by `ManagedPlatformAddressWallet.transfer`
    /// (dashpay/platform#3626) across the account holding the highest-balance
    /// row; change goes to the lowest-indexed unused HD address in that
    /// account (mirrors the Receive screen's selection). The returned
    /// `[UpdatedBalance]` rows are applied to SwiftData as a
    /// belt-and-suspenders alongside the Rust persister.
    public func transfer(
        destination: String,
        amount: UInt64
    ) async throws {
        guard isRunning,
              let addressWallet = platformAddressWallet,
              let container = modelContainer,
              let walletId = wallet?.walletId,
              let network = runningNetwork
        else { throw SendError.coordinatorNotReady }

        guard let recipient = Self.parsePlatformRecipient(bech32m: destination)
        else { throw SendError.invalidDestination }
        // FFI's `PlatformAddressFFI → PlatformAddress` conversion in
        // rs-platform-wallet-ffi only accepts P2PKH; surface a clear error
        // rather than letting Rust emit "Unsupported address type".
        guard recipient.ffiAddressType == 0
        else { throw SendError.p2shNotSupported }

        let context = container.mainContext

        let allDescriptor = FetchDescriptor<PersistentPlatformAddress>(
            predicate: #Predicate<PersistentPlatformAddress> { $0.walletId == walletId })
        let allRows = try context.fetch(allDescriptor)
        guard let senderRow = allRows
            .filter({ $0.balance > 0 })
            .max(by: { $0.balance < $1.balance })
        else { throw SendError.noFundedAddress }
        let senderAccountIndex = senderRow.accountIndex

        // Lowest-indexed unused zero-balance row scoped to the sender's
        // account, matching ReceiveAddressView's selection rule. Exclude
        // the recipient hash — a self-send to the wallet's own next-unused
        // address would otherwise pick that same row for change, and
        // `ManagedPlatformAddressWallet.transfer` rejects collisions with
        // a `changeAddress collides with a recipient address` error.
        // Nil falls back to the wrapper's internal "smallest non-recipient"
        // pick — workable but lands change on an existing balance row.
        let recipientHash = recipient.hash
        let changeRow = allRows
            .filter { $0.accountIndex == senderAccountIndex
                      && !$0.isUsed
                      && $0.balance == 0
                      && $0.addressHash != recipientHash }
            .min(by: { $0.addressIndex < $1.addressIndex })
        let change = changeRow.map {
            ManagedPlatformAddressWallet.ChangeAddress(
                addressType: $0.addressType,
                hash: $0.addressHash)
        }

        let output = ManagedPlatformAddressWallet.TransferOutput(
            addressType: recipient.ffiAddressType,
            hash: recipient.hash,
            credits: amount)

        let signer = KeychainSigner(
            modelContainer: container,
            network: network)

        Self.logger.info(
            "🛰️ PLATFORM-SEND :: → \(destination, privacy: .public) :: amount=\(amount) account=\(senderAccountIndex) change=\(changeRow?.address ?? "fallback", privacy: .public)")

        let updated = try await addressWallet.transfer(
            accountIndex: senderAccountIndex,
            outputs: [output],
            changeAddress: change,
            signer: signer)

        // Idempotent with the Rust persister callback; keeps @Query-bound
        // rows fresh even if the callback ordering ever changes.
        for entry in updated {
            let entryHash = entry.hash
            let descriptor = FetchDescriptor<PersistentPlatformAddress>(
                predicate: #Predicate { $0.addressHash == entryHash })
            guard let row = try? context.fetch(descriptor).first else { continue }
            row.balance = entry.balance
            row.nonce = entry.nonce
            row.isUsed = true
            row.lastUpdated = Date()
        }
        try? context.save()

        Task { await self.syncNow() }
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
        guard let network = resolveCurrentNetwork() else {
            Self.logger.info("🛰️ PLATFORM-ADDR :: skipping start — unsupported network")
            return
        }
        await performStart(network: network)
    }

    private func performStart(network: Network) async {
        if isRunning && runningNetwork == network {
            Self.logger.info("🛰️ PLATFORM-ADDR :: start ignored — already running on \(network.rawValue, privacy: .public)")
            return
        }

        if walletManager != nil {
            await performStop(deletingPersistedWallet: false)
        }

        Self.logger.info("🛰️ PLATFORM-ADDR :: starting for \(network.rawValue, privacy: .public)")

        let manager: PlatformWalletManager
        let resolvedWallet: ManagedPlatformWallet
        do {
            (manager, resolvedWallet) = try SwiftDashSDKHost.shared.start(network: network)
        } catch {
            Self.logger.error("🛰️ PLATFORM-ADDR :: host.start failed: \(String(describing: error), privacy: .public)")
            lastError = error.localizedDescription
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

        self.sdk = SwiftDashSDKHost.shared.sdk
        self.modelContainer = SwiftDashSDKHost.shared.modelContainer
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

    private func performStop(deletingPersistedWallet: Bool) async {
        // Mirror SwiftExampleApp's delete-wallet sequence
        // (`WalletDetailView.deleteWallet()` + `rebindWalletScopedServices()`):
        //
        //   1. When wiping, delete the `PersistentWallet` row from SwiftData
        //      FIRST. After this, any in-flight BLAST callback that does
        //      `walletNetwork(walletId:)` gets an empty fetch and early-exits,
        //      instead of traversing deeper and hitting refs that will be
        //      dropped by the teardown below.
        //      Plain stops (app restart, wallet-material change, network
        //      switch) must NOT delete the row — that would erase address +
        //      balance history and force a full resync every launch.
        //   2. Cancel Combine subscriptions.
        //   3. `stopPlatformAddressSync()` on the still-alive manager.
        //   4. Drop Swift-side handles. `modelContainer` stays alive through
        //      the reset — the next `performStart` overwrites it, and keeping
        //      it referenced here means SwiftData contexts captured by
        //      Rust-side persister closures don't dangle while tokio winds down.
        if deletingPersistedWallet {
            deletePersistedWalletIfAny()
        }

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
        guard let container = modelContainer else { return }
        let context = container.mainContext

        if let walletId = wallet?.walletId {
            let walletDescriptor = FetchDescriptor<PersistentWallet>(
                predicate: #Predicate<PersistentWallet> { $0.walletId == walletId })
            do {
                let rows = try context.fetch(walletDescriptor)
                for row in rows {
                    context.delete(row)
                }
                Self.logger.info(
                    "🛰️ PLATFORM-ADDR :: deleted \(rows.count) PersistentWallet row(s) before stop")
            } catch {
                Self.logger.error(
                    "🛰️ PLATFORM-ADDR :: PersistentWallet cleanup threw: \(String(describing: error), privacy: .public)")
            }
        }

        // Drop the BLAST sync watermark too. `PersistentPlatformAddressesSyncState` is a
        // standalone model — no cascade from `PersistentWallet` — and it's
        // keyed per network (`platform-sync:<network>` scope id, one row per
        // network). Leaving it behind makes BLAST resume from the last-known
        // block on the re-created wallet; the trunk/branch/compact rescan
        // that would re-discover balances for the freshly-derived address
        // pool is skipped, and the UI stays at 0 forever.
        if let netRaw = runningNetwork?.rawValue {
            let syncDescriptor = FetchDescriptor<PersistentPlatformAddressesSyncState>(
                predicate: #Predicate<PersistentPlatformAddressesSyncState> { $0.networkRaw == netRaw })
            do {
                let rows = try context.fetch(syncDescriptor)
                for row in rows {
                    context.delete(row)
                }
                Self.logger.info(
                    "🛰️ PLATFORM-ADDR :: deleted \(rows.count) PersistentPlatformAddressesSyncState row(s) for network \(netRaw, privacy: .public)")
            } catch {
                Self.logger.error(
                    "🛰️ PLATFORM-ADDR :: PersistentPlatformAddressesSyncState cleanup threw: \(String(describing: error), privacy: .public)")
            }
        }

        do {
            try context.save()
        } catch {
            Self.logger.error(
                "🛰️ PLATFORM-ADDR :: wipe-cleanup save threw: \(String(describing: error), privacy: .public)")
        }
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

    private func resolveCurrentNetwork() -> Network? {
        let chain = DWEnvironment.sharedInstance().currentChain
        if chain.isMainnet() { return .mainnet }
        if chain.isTestnet() { return .testnet }
        return nil
    }

    struct PlatformRecipient {
        let ffiAddressType: UInt8  // 0 = P2PKH, 1 = P2SH
        let hash: Data             // 20 bytes
    }

    /// Decode a DIP-0018 bech32m address (HRP `dash`/`tdash`) into the FFI
    /// discriminant + 20-byte hash that `ManagedPlatformAddressWallet`
    /// expects. Per rs-dpp's `address_funds/platform_address.rs`, only
    /// `0xb0` (P2PKH) and `0x80` (P2SH) are valid wire bytes — `0x00`/`0x01`
    /// are storage bytes and must never appear in a `tdash1…`/`dash1…`
    /// string.
    static func parsePlatformRecipient(bech32m: String) -> PlatformRecipient? {
        guard let decoded = Bech32m.decode(bech32m.lowercased()),
              decoded.hrp == "dash" || decoded.hrp == "tdash",
              decoded.data.count == 21
        else { return nil }

        let ffiType: UInt8
        switch decoded.data[0] {
        case 0xb0: ffiType = 0
        case 0x80: ffiType = 1
        default: return nil
        }
        return PlatformRecipient(
            ffiAddressType: ffiType,
            hash: decoded.data.subdata(in: 1..<21))
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
        case p2shNotSupported
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
            case .p2shNotSupported:
                return NSLocalizedString(
                    "P2SH platform addresses aren't supported yet. Use a P2PKH recipient.",
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
