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
import SwiftDashSDK
import SwiftData
import UIKit

/// Decides when the app should supplement the SDK's regular shielded polling
/// with a forced pass. External same-seed spends do not produce a local
/// invalidation signal, and iOS may suspend the SDK's background timer, so a
/// bounded freshness check is required even while Core sync is caught up.
struct ShieldedSyncFreshnessPolicy {
    static let watchdogInterval: TimeInterval = 15
    static let maximumFullScanAge: TimeInterval = 90
    /// The ordinary background loop observes the SDK's caught-up cooldown.
    /// Explicit `syncShieldedNow()` requests use the SDK's `force=true` path
    /// and bypass it; attended Receive sessions use that path independently.
    static let foregroundFreshnessGrace: TimeInterval = 30

    static func shouldRefreshForWatchdog(
        now: Date,
        lastFullScanAt: Date?,
        monitoringStartedAt: Date,
        isSyncing: Bool,
        refreshInFlight: Bool
    ) -> Bool {
        guard !isSyncing, !refreshInFlight else { return false }
        let freshnessBaseline = lastFullScanAt ?? monitoringStartedAt
        return now.timeIntervalSince(freshnessBaseline) >= maximumFullScanAge
    }

    static func shouldRefreshOnForeground(
        now: Date,
        lastFullScanAt: Date?,
        monitoringStartedAt: Date,
        isSyncing: Bool,
        refreshInFlight: Bool
    ) -> Bool {
        guard !isSyncing, !refreshInFlight else { return false }
        let freshnessBaseline = lastFullScanAt ?? monitoringStartedAt
        return now.timeIntervalSince(freshnessBaseline) >= foregroundFreshnessGrace
    }
}

enum PlatformAccountAvailability: Equatable {
    case unknown
    case available
    case unavailable
}

struct PlatformAccountAvailabilityPolicy {
    static func resolve(
        hasWalletRecord: Bool,
        hasPlatformPaymentAccount: Bool
    ) -> PlatformAccountAvailability {
        guard hasWalletRecord else { return .unknown }
        return hasPlatformPaymentAccount ? .available : .unavailable
    }
}

struct PlatformSyncRearmPolicy {
    static func requiresRuntimeRearm(
        isRunning: Bool,
        hasWalletManager: Bool
    ) -> Bool {
        !isRunning || !hasWalletManager
    }
}

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
    /// True for the whole Clear sequence (Rust reset → SwiftData zeroing
    /// → display wipe → loop re-arm); gates the Sync Now / Clear buttons.
    @Published public private(set) var isClearing: Bool = false
    @Published public private(set) var lastSyncTime: Date? = nil
    @Published public private(set) var lastError: String? = nil

    /// Startup failure of `platformAddressWallet()`, held apart from
    /// `lastError` because it outlives the events that clear it.
    ///
    /// The address wallet and the manager's Platform address sync fail
    /// independently: the sync can complete successfully while this wallet is
    /// missing, and every success clears `lastError`. Publishing the startup
    /// failure only once would let the first successful pass erase it, leaving
    /// the status screen reporting a healthy sync over address surfaces that
    /// cannot work. Kept here and re-published wherever `lastError` is cleared
    /// on success. Cleared by `clearDisplay()`, which runs on teardown, wipe
    /// and network-switch preparation — every path that invalidates the wallet
    /// this error was recorded against — and overwritten by the next start.
    private var addressWalletStartupError: String?
    @Published private(set) var platformAccountAvailability: PlatformAccountAvailability = .unknown

    @Published public private(set) var platformBalance: UInt64 = 0
    @Published public private(set) var shieldedBalance: UInt64 = 0
    /// True while a shielded spend has been observed but its change note has
    /// not reached the local scan yet. During this window `shieldedBalance`
    /// keeps the last reliable value instead of publishing a transient zero.
    @Published public private(set) var isShieldedBalanceReconciling: Bool = false
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

    /// Read-only handle to the live SDK wallet manager plus the wallet it was
    /// started for (nil until BLAST starts). The Sync Info diagnostic screens
    /// observe the manager's published sync mirrors (`dashPaySyncIsSyncing`,
    /// `shieldedSyncIsSyncing`, …) through this; lifecycle stays owned here.
    public var platformWalletManager: PlatformWalletManager? { walletManager }
    public var activeWalletId: Data? { wallet?.walletId }

    private var syncEventCancellable: AnyCancellable?
    private var syncStateCancellable: AnyCancellable?
    private var shieldedEventCancellable: AnyCancellable?
    private var shieldedForegroundCancellable: AnyCancellable?
    private var shieldedFreshnessTask: Task<Void, Never>?
    private var shieldedRefreshTask: Task<Void, Never>?
    private var shieldedRefreshGeneration: UInt64 = 0
    private var shieldedMonitoringStartedAt = Date()
    private var lastFullShieldedSyncAt: Date?
    private var shieldedReconciliationTask: Task<Void, Never>?
    private var latestObservedShieldedBalance: UInt64 = 0

    /// Long-lived resolver for the shielded sub-wallet bind in `performStart`.
    /// Stored (not local) because `MnemonicResolver` hands Rust an unretained
    /// pointer, so ARC must own it across the bind — mirrors SwiftExampleApp
    /// holding one `shieldedResolver` for the app lifetime. Reads the mnemonic
    /// from the keychain silently (no biometric prompt).
    private let shieldedResolver = MnemonicResolver()

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

        if PlatformSyncRearmPolicy.requiresRuntimeRearm(
            isRunning: isRunning,
            hasWalletManager: walletManager != nil
        ) {
            lastError = nil
            await SwiftDashSDKWalletRuntime.shared.rearmPlatformSync()
        }

        guard let manager = walletManager else {
            // A missing SDK wallet is a valid post-wipe state, not a Platform
            // sync failure. When wallet material does exist, the serialized
            // runtime re-arm above owns the concrete start error and leaves it
            // in `lastError`. A wallet that exists without a Platform Payment
            // account is handled by `platformAccountAvailability`.
            if !WalletEnvironment.hasSDKWallet {
                platformAccountAvailability = .unavailable
                lastError = nil
            } else if platformAccountAvailability != .unavailable && lastError == nil {
                lastError = "Platform sync could not be started"
            }
            return
        }

        // Re-arming starts the background loop as part of binding the runtime.
        // Its seeded publisher may have flipped this while we were awaiting
        // the lifecycle queue, so do not launch a competing one-shot sync.
        guard !isSyncing else { return }

        do {
            if try !manager.isPlatformAddressSyncRunning() {
                try manager.startPlatformAddressSync()
            }
            isSyncing = true
            lastError = addressWalletStartupError
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
        let senderAccountIndex = try highestBalanceAccountIndex(context: context, walletId: walletId)

        let output = ManagedPlatformAddressWallet.TransferOutput(
            addressType: recipient.ffiAddressType,
            hash: recipient.hash,
            credits: amount)

        let signer = KeychainSigner(
            modelContainer: container,
            network: network)

        Self.logger.info(
            "🛰️ PLATFORM-SEND :: → \(destination, privacy: .public) :: amount=\(amount) account=\(senderAccountIndex)")

        // No change routing since the SDK's credit-balance transfer model:
        // the Rust auto-selector partially consumes the last input and the
        // surplus stays on the source address (no change output exists).
        let updated = try await addressWallet.transfer(
            accountIndex: senderAccountIndex,
            outputs: [output],
            signer: signer)

        applyUpdatedBalances(updated, context: context)

        Task { await self.syncNow() }
    }

    /// Account index holding the highest-balance Platform address — the
    /// account `transfer`/`withdrawAllToCore` spend from.
    private func highestBalanceAccountIndex(context: ModelContext, walletId: Data) throws -> UInt32 {
        try highestBalanceRow(context: context, walletId: walletId).accountIndex
    }

    /// The highest-balance funded Platform address row.
    private func highestBalanceRow(context: ModelContext, walletId: Data) throws -> PersistentPlatformAddress {
        let allDescriptor = FetchDescriptor<PersistentPlatformAddress>(
            predicate: #Predicate<PersistentPlatformAddress> { $0.walletId == walletId })
        let allRows = try context.fetch(allDescriptor)
        guard let senderRow = allRows
            .filter({ $0.balance > 0 })
            .max(by: { $0.balance < $1.balance })
        else { throw SendError.noFundedAddress }
        return senderRow
    }

    /// Apply the FFI-reported per-address balances to SwiftData — idempotent
    /// with the Rust persister callback; keeps @Query-bound rows fresh even
    /// if the callback ordering ever changes.
    private func applyUpdatedBalances(
        _ updated: [ManagedPlatformAddressWallet.UpdatedBalance],
        context: ModelContext
    ) {
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
    }

    // MARK: - Core ↔ Platform balance movement

    /// SDK-owned affordability preflight for Platform Payment → Shielded.
    ///
    /// The Platform balance shown by this coordinator is the sum of every
    /// derived address, but the shield transition can only spend the suffix
    /// selected by the Rust wallet. Keep that selection rule in the SDK and
    /// expose its exact result to the internal-transfer UI instead of
    /// reimplementing it from `derivedAddresses` here.
    public func preflightShield(
        paymentAccount: UInt32 = 0
    ) async throws -> PlatformWalletManager.ShieldedShieldPreflight {
        guard isRunning,
              let manager = walletManager,
              let walletId = wallet?.walletId
        else { throw SendError.coordinatorNotReady }

        return try await manager.shieldedShieldPreflight(
            walletId: walletId,
            paymentAccount: paymentAccount)
    }

    /// Preflight of the full-balance Platform → Core withdrawal for the
    /// account holding the highest Platform address balance (the same
    /// account `transfer` spends from). See `withdrawAllToCore` for why
    /// there is no partial-amount form.
    public func preflightWithdrawal() async throws -> ManagedPlatformAddressWallet.WithdrawalPreflight {
        guard isRunning,
              let addressWallet = platformAddressWallet,
              let container = modelContainer,
              let walletId = wallet?.walletId
        else { throw SendError.coordinatorNotReady }
        let accountIndex = try highestBalanceAccountIndex(
            context: container.mainContext, walletId: walletId)
        return try await addressWallet.preflightWithdrawal(accountIndex: accountIndex)
    }

    /// Withdraw the selected account's ENTIRE withdrawable Platform credit
    /// balance to `coreAddress`. The SDK's address-credit withdrawal has no
    /// partial-amount form — AUTO input selection withdraws every non-dust
    /// input, less the transition fee — so callers must present this as a
    /// full-balance operation. The L1 payout arrives asynchronously once the
    /// chain processes the withdrawal.
    public func withdrawAllToCore(address coreAddress: String) async throws {
        guard isRunning,
              let addressWallet = platformAddressWallet,
              let container = modelContainer,
              let walletId = wallet?.walletId,
              let network = runningNetwork
        else { throw SendError.coordinatorNotReady }
        let context = container.mainContext
        let accountIndex = try highestBalanceAccountIndex(context: context, walletId: walletId)
        let signer = KeychainSigner(modelContainer: container, network: network)

        Self.logger.info("🛰️ PLATFORM-WITHDRAW :: full balance → core account=\(accountIndex)")

        let updated = try await addressWallet.withdraw(
            accountIndex: accountIndex,
            coreAddress: coreAddress,
            signer: signer)

        applyUpdatedBalances(updated, context: context)
        Task { await self.syncNow() }
    }

    /// Partial Platform → Core withdrawal: pays out exactly `amountCredits`
    /// to `coreAddress`, drawn from the single largest-balance Platform
    /// address (explicit input selection). The transition fee is deducted
    /// from that address's REMAINING balance, so it must retain at least
    /// `feeHeadroomCredits` after the withdrawal — pass the preflight's
    /// `estimatedFee` (a conservative bound for a single input), or nil to
    /// preflight here. Amounts above the single-address cap should go
    /// through `withdrawAllToCore` (AUTO, all addresses) instead.
    public func withdrawToCore(
        amountCredits: UInt64,
        address coreAddress: String,
        feeHeadroomCredits: UInt64? = nil
    ) async throws {
        guard isRunning,
              let addressWallet = platformAddressWallet,
              let container = modelContainer,
              let walletId = wallet?.walletId,
              let network = runningNetwork
        else { throw SendError.coordinatorNotReady }
        let context = container.mainContext
        let senderRow = try highestBalanceRow(context: context, walletId: walletId)

        let headroom: UInt64
        if let feeHeadroomCredits {
            headroom = feeHeadroomCredits
        } else {
            headroom = try await addressWallet
                .preflightWithdrawal(accountIndex: senderRow.accountIndex)
                .estimatedFee
        }
        guard senderRow.balance >= headroom,
              amountCredits <= senderRow.balance - headroom
        else { throw SendError.noFundedAddress }

        let signer = KeychainSigner(modelContainer: container, network: network)
        let input = ManagedPlatformAddressWallet.WithdrawalInput(
            addressType: 0,
            hash: senderRow.addressHash,
            credits: amountCredits)

        Self.logger.info(
            "🛰️ PLATFORM-WITHDRAW :: partial amount=\(amountCredits) account=\(senderRow.accountIndex)")

        let updated = try await addressWallet.withdraw(
            accountIndex: senderRow.accountIndex,
            coreAddress: coreAddress,
            inputs: [input],
            signer: signer)

        applyUpdatedBalances(updated, context: context)
        Task { await self.syncNow() }
    }

    /// Fund the wallet's own Platform balance from the Core L1 balance via
    /// an asset lock (funding type 4, `AssetLockAddressTopUp`). `amountDuffs`
    /// is locked on L1; the credited amount is that value minus the fees the
    /// Rust side carves from the single remainder recipient (the wallet's
    /// own next unused Platform address).
    public func fundFromCore(amountDuffs: UInt64) async throws {
        let (addressWallet, container, recipient, accountIndex) = try resolveFundEnvironment()
        let signer = KeychainSigner(modelContainer: container, network: runningNetwork!)

        Self.logger.info("🛰️ PLATFORM-FUND :: core → platform amount=\(amountDuffs) account=\(accountIndex)")

        let updated = try await addressWallet.fundFromAssetLock(
            amountDuffs: amountDuffs,
            fundingAccountIndex: 0,
            platformAccountIndex: accountIndex,
            recipients: [recipient],
            signer: signer)

        applyUpdatedBalances(updated, context: container.mainContext)
        await ShieldedTxLookup.shared.refresh(reason: "platform-fund-completed")
        Task { await self.syncNow() }
    }

    /// Resume a stuck Core → Platform funding whose asset lock is committed
    /// on-chain (Broadcast/IS-locked/CL-locked) but whose address-funding
    /// state transition never landed. Sibling of `fundFromCore` — picks up
    /// the existing outpoint instead of building (and stranding) a second
    /// lock. See `ShieldedTransferCoordinator.resumeAssetLock` for the same
    /// pattern on the shielded route.
    public func resumeFundFromCore(outPointTxid: Data, outPointVout: UInt32) async throws {
        let (addressWallet, container, recipient, accountIndex) = try resolveFundEnvironment()
        let signer = KeychainSigner(modelContainer: container, network: runningNetwork!)

        Self.logger.info("🛰️ PLATFORM-FUND :: resume core → platform vout=\(outPointVout)")

        let updated = try await addressWallet.resumeFundFromAssetLock(
            outPointTxid: outPointTxid,
            outPointVout: outPointVout,
            platformAccountIndex: accountIndex,
            recipients: [recipient],
            signer: signer)

        applyUpdatedBalances(updated, context: container.mainContext)
        await ShieldedTxLookup.shared.refresh(reason: "platform-fund-resume-completed")
        Task { await self.syncNow() }
    }

    /// Shared readiness + recipient resolution for `fundFromCore` /
    /// `resumeFundFromCore`: the single credits-nil recipient is the
    /// remainder output (absorbs the locked value less fees), pointed at the
    /// wallet's own next receive address.
    private func resolveFundEnvironment() throws -> (
        wallet: ManagedPlatformAddressWallet,
        container: ModelContainer,
        recipient: ManagedPlatformAddressWallet.FundFromAssetLockRecipient,
        accountIndex: UInt32
    ) {
        guard isRunning,
              let addressWallet = platformAddressWallet,
              let container = modelContainer,
              runningNetwork != nil
        else { throw SendError.coordinatorNotReady }
        guard let target = derivedAddresses.nextReceiveAddress,
              let parsed = Self.parsePlatformRecipient(bech32m: target.address),
              parsed.ffiAddressType == 0
        else { throw SendError.noPlatformReceiveAddress }
        let recipient = ManagedPlatformAddressWallet.FundFromAssetLockRecipient(
            addressType: 0, hash: parsed.hash, credits: nil)
        return (addressWallet, container, recipient, target.accountIndex)
    }

    /// Full local wipe of the platform-address sync state — the Sync Info
    /// screen's "Clear" button. Ported from the SwiftExampleApp
    /// `PlatformBalanceSyncService.clearLocalState` contract:
    ///
    /// 1. Reset the Rust-owned incremental-sync watermark FIRST
    ///    (`resetPlatformAddressSyncState`) — without this, the in-memory
    ///    watermark survives and the next Sync Now resumes incrementally
    ///    (Recent queries only) instead of the full trunk/branch rescan.
    ///    Fail closed: on error, surface it and keep the current display
    ///    rather than showing a false "cleared" state.
    /// 2. Zero the volatile balance/sync fields of this network's
    ///    `PersistentPlatformAddress` rows IN PLACE — never delete them:
    ///    they are durable derivation state the rescan upserts against
    ///    (the balance callback skips rows it can't find, and no
    ///    in-session sync re-emits them).
    /// 3. Delete the network's `PersistentPlatformAddressesSyncState`
    ///    watermark rows outright — pure volatile state, recreated by
    ///    the next sync.
    /// 4. Clear the published display, then re-arm the background loop
    ///    (the Rust reset deliberately leaves it stopped).
    public func clearLocalState() async {
        guard !isClearing else { return }
        guard let manager = walletManager else {
            // BLAST never started — nothing Rust-side or persisted to
            // reset; wiping the display is the whole job.
            clearDisplay()
            return
        }
        isClearing = true
        defer { isClearing = false }

        do {
            try await manager.resetPlatformAddressSyncState()
        } catch {
            lastError = "Failed to reset platform-address sync state: \(error.localizedDescription)"
            Self.logger.error("🛰️ PLATFORM-ADDR :: clear reset failed: \(String(describing: error), privacy: .public)")
            return
        }

        if let container = modelContainer, let network = runningNetwork {
            do {
                let context = container.mainContext
                let networkRaw = network.rawValue
                let wallets = try context.fetch(FetchDescriptor<PersistentWallet>(
                    predicate: #Predicate { $0.networkRaw == networkRaw }))
                let walletIds = Set(wallets.map(\.walletId))
                let addresses = try context.fetch(FetchDescriptor<PersistentPlatformAddress>())
                for row in addresses where walletIds.contains(row.walletId) {
                    row.balance = 0
                    row.nonce = 0
                    row.isUsed = false
                    row.firstSeenHeight = 0
                    row.lastSeenHeight = 0
                    row.lastUpdated = Date()
                }
                let syncStates = try context.fetch(FetchDescriptor<PersistentPlatformAddressesSyncState>())
                for row in syncStates where row.networkRaw == networkRaw {
                    context.delete(row)
                }
                try context.save()
            } catch {
                lastError = "Failed to clear persisted platform-address state: \(error.localizedDescription)"
                Self.logger.error("🛰️ PLATFORM-ADDR :: clear persist failed: \(String(describing: error), privacy: .public)")
                return
            }
        }

        clearDisplay()

        do {
            try manager.startPlatformAddressSync()
        } catch {
            lastError = "startPlatformAddressSync failed after clear: \(error.localizedDescription)"
            Self.logger.error("🛰️ PLATFORM-ADDR :: post-clear restart failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Cancel every subscription/task that writes the published mirrors. Pure
    /// Swift-side teardown (no FFI call), so it is safe to run ahead of the
    /// serialized stop — `performStop` and `prepareForNetworkSwitch` share it
    /// rather than keeping two lists of cancellables in step by hand.
    private func detachSyncSubscriptions() {
        syncEventCancellable?.cancel()
        syncEventCancellable = nil
        syncStateCancellable?.cancel()
        syncStateCancellable = nil
        shieldedEventCancellable?.cancel()
        shieldedEventCancellable = nil
        shieldedForegroundCancellable?.cancel()
        shieldedForegroundCancellable = nil
        shieldedFreshnessTask?.cancel()
        shieldedFreshnessTask = nil
        shieldedRefreshGeneration &+= 1
        shieldedRefreshTask?.cancel()
        shieldedRefreshTask = nil
        lastFullShieldedSyncAt = nil
    }

    /// Drop the outgoing network's Platform and Shielded balances the moment a
    /// network switch is requested, ahead of the runtime's serialized stop.
    ///
    /// `performStop` only runs once the lifecycle queue reaches it, and BLAST /
    /// shielded events from the previous network keep repainting the mirrors
    /// until then — so the home screen would otherwise show the old network's
    /// funds for the whole transition.
    public func prepareForNetworkSwitch() {
        detachSyncSubscriptions()
        clearDisplay()
    }

    /// Clear the UI counters/display without tearing down the sync loop.
    public func clearDisplay() {
        shieldedReconciliationTask?.cancel()
        shieldedReconciliationTask = nil
        platformBalance = 0
        shieldedBalance = 0
        latestObservedShieldedBalance = 0
        isShieldedBalanceReconciling = false
        activeAddressCount = 0
        derivedAddresses = []
        checkpointHeight = 0
        chainTipHeight = 0
        lastSyncHeight = 0
        lastKnownRecentBlock = 0
        lastSyncBlockTime = nil
        lastSyncTime = nil
        lastError = nil
        addressWalletStartupError = nil
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
            (manager, resolvedWallet) = try await SwiftDashSDKHost.shared.start(network: network)
        } catch {
            Self.logger.error("🛰️ PLATFORM-ADDR :: host.start failed: \(String(describing: error), privacy: .public)")
            lastError = error.localizedDescription
            return
        }

        let accountAvailability = resolvePlatformAccountAvailability(
            walletId: resolvedWallet.walletId)
        let addressWallet: ManagedPlatformAddressWallet?
        // Carried to the end rather than returned on: see below.
        var addressWalletError: String?
        do {
            addressWallet = try resolvedWallet.platformAddressWallet()
        } catch {
            addressWallet = nil
            if accountAvailability == .unavailable {
                // A wallet can legitimately have Shielded state without a
                // DIP-17 Platform Payment account. Keep the shared manager
                // alive for Shielded/DashPay and expose a neutral UI state.
                Self.logger.info(
                    "🛰️ PLATFORM-ADDR :: no Platform Payment account; continuing without address wallet")
            } else {
                // Report the failure, but do not abort the start. Shielded,
                // the DashPay sync loop and identity recovery share the
                // manager, not the address wallet, and returning here took all
                // three down with it: a restored wallet that hit this on the
                // one start it gets per session lost its identity — and with
                // it every contact and all contact payment history — until the
                // app was relaunched. `addressWallet` is already an optional
                // the rest of this method handles (the branch above sets it to
                // nil and continues), so the only difference here is that
                // `lastError` explains why the address surfaces are empty.
                Self.logger.error("🛰️ PLATFORM-ADDR :: platformAddressWallet() failed: \(String(describing: error), privacy: .public)")
                addressWalletError = "platformAddressWallet failed: \(error.localizedDescription)"
            }
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

        // Bind the shielded sub-wallet so `shieldedDefaultAddress` resolves and
        // the shielded sync loop (→ shielded balance) runs. Mirrors
        // SwiftExampleApp.rebindWalletScopedServices. Best-effort: a failure
        // here must NOT abort the platform-address start above, and must NOT
        // touch `lastError` (that field drives the platform-sync status UI).
        // If the bind fails, the to-shielded transfer still surfaces its own
        // clear "not bound" error at transfer time.
        do {
            let dbPath = try SwiftDashSDKHost.shared.shieldedTreeDBPath(for: network)
            try manager.configureShielded(dbPath: dbPath)
            try manager.bindShielded(walletId: resolvedWallet.walletId, resolver: shieldedResolver)
            if try !manager.isShieldedSyncRunning() {
                try manager.startShieldedSync()
            }
            Self.logger.info("🛡️ SHIELD :: bound + sync started for \(network.rawValue, privacy: .public)")
        } catch {
            Self.logger.error("🛡️ SHIELD :: bind failed: \(String(describing: error), privacy: .public)")
        }

#if DASHPAY
        // Start the DashPay background sync (contact requests, own + contact
        // profiles, contact info, DashPay payment reconciliation — the Rust
        // coordinator sequences six per-wallet steps each pass, default 15s).
        // Rows land in SwiftData (PersistentDashpayContactRequest /
        // PersistentDashpayContactProfile) via the persister callback, which is
        // what the contacts read model queries (migration row #18). Wallets
        // with no identity get a harmless empty pass — errors are
        // log-and-continue per wallet on the Rust side. Best-effort like the
        // shielded block above: a failure must not abort the BLAST start and
        // must not touch `lastError`.
        do {
            if try !manager.isDashPaySyncRunning() {
                try manager.startDashPaySync()
            }
            Self.logger.info("👥 DASHPAY-SYNC :: started for \(network.rawValue, privacy: .public)")
        } catch {
            Self.logger.error("👥 DASHPAY-SYNC :: startDashPaySync failed: \(String(describing: error), privacy: .public)")
        }

        // Start the recurring DPNS username-marketplace sync (tracks the
        // wallet identities' names with sale state, detects sold/
        // transferred departures, refreshes seller balances). Same
        // best-effort contract as the blocks above; the marketplace
        // screen's pull-to-refresh (`syncDpnsMarketplace`) still works
        // without the loop.
        do {
            if try !manager.isDpnsSyncRunning() {
                try manager.startDpnsSync()
            }
            Self.logger.info("🏷️ DPNS-SYNC :: started for \(network.rawValue, privacy: .public)")
        } catch {
            Self.logger.error("🏷️ DPNS-SYNC :: startDpnsSync failed: \(String(describing: error), privacy: .public)")
        }
#endif

        self.sdk = SwiftDashSDKHost.shared.sdk
        self.modelContainer = SwiftDashSDKHost.shared.modelContainer
        self.walletManager = manager
        self.wallet = resolvedWallet
        self.platformAddressWallet = addressWallet
        self.platformAccountAvailability = accountAvailability
        self.runningNetwork = network
        self.isRunning = true
        self.addressWalletStartupError = addressWalletError
        self.lastError = addressWalletError

        await subscribeToManager(manager: manager, walletId: resolvedWallet.walletId)
        refreshDerivedAddresses()

        // Hand the shielded diagnostics monitor the new manager generation.
        // Attach AFTER the state above is committed so the monitor's initial
        // bound-state / notes-synced reads see the running coordinator.
        ShieldedSyncMonitor.shared.attach(
            manager: manager,
            walletId: resolvedWallet.walletId,
            modelContainer: SwiftDashSDKHost.shared.modelContainer)

#if DASHPAY
        // A restored seed can already own a Platform identity even though this
        // install's SwiftData store is empty. Recovery now runs as step 1 of
        // `DashPayContactAddressReadiness`, ahead of Core SPV, because the
        // contacts and contact accounts that depend on it have to exist before
        // the first filter set is built. This call stays as the backstop for
        // the orders that do not go through the SPV coordinator — a Platform
        // sync re-arm, or an SPV start that failed — and is a no-op once the
        // identity has been adopted.
        if let container = SwiftDashSDKHost.shared.modelContainer {
            await DWSameSeedIdentityRecoveryCoordinator.shared.recoverIfNeeded(
                wallet: resolvedWallet,
                modelContainer: container,
                network: network)
        }
#endif

        Self.logger.info("🛰️ PLATFORM-ADDR :: started for \(network.rawValue, privacy: .public)")
    }

    private func performStop(deletingPersistedWallet: Bool) async {
        // Detach the shielded diagnostics monitor before the manager handles
        // drop, so it never observes a manager whose loops are being torn down.
        ShieldedSyncMonitor.shared.detach()

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

        detachSyncSubscriptions()

        if let manager = walletManager {
            do {
                if try manager.isPlatformAddressSyncRunning() {
                    try manager.stopPlatformAddressSync()
                }
                Self.logger.info("🛰️ PLATFORM-ADDR :: stopped")
            } catch {
                Self.logger.error("🛰️ PLATFORM-ADDR :: stopPlatformAddressSync threw: \(String(describing: error), privacy: .public)")
            }
            // Stop the shielded sync loop alongside BLAST so it doesn't outlive
            // the manager (also covers network switch — performStart calls
            // performStop first). Independent do/catch so a shielded-stop throw
            // can't skip, and isn't skipped by, the BLAST stop above.
            do {
                if try manager.isShieldedSyncRunning() {
                    try manager.stopShieldedSync()
                }
                Self.logger.info("🛡️ SHIELD :: stopped")
            } catch {
                Self.logger.error("🛡️ SHIELD :: stopShieldedSync threw: \(String(describing: error), privacy: .public)")
            }
#if DASHPAY
            // Stop the DashPay sync loop alongside BLAST/shielded so it
            // doesn't outlive the manager (also covers network switch —
            // performStart calls performStop first). Independent do/catch,
            // same isolation rationale as the shielded stop above.
            do {
                if try manager.isDashPaySyncRunning() {
                    try manager.stopDashPaySync()
                }
                Self.logger.info("👥 DASHPAY-SYNC :: stopped")
            } catch {
                Self.logger.error("👥 DASHPAY-SYNC :: stopDashPaySync threw: \(String(describing: error), privacy: .public)")
            }
#endif
        }

        walletManager = nil
        wallet = nil
        platformAddressWallet = nil
        sdk = nil
        runningNetwork = nil
        isRunning = false
        platformAccountAvailability = .unknown
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

    private func subscribeToManager(manager: PlatformWalletManager, walletId: Data) async {
        shieldedMonitoringStartedAt = Date()
        lastFullShieldedSyncAt = nil

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

        // Seed once from whatever the manager already saw (the publisher only
        // fires on new events), then mirror the shielded balance from each
        // completed shielded sync pass. Balance is in credits (1e11/DASH).
        // Cooldown skips carry a zero payload, so they are never a valid seed.
        if let result = manager.lastShieldedSyncEvent?.result(for: walletId),
           result.success,
           !result.cooldownSkip {
            shieldedBalance = result.balance
            latestObservedShieldedBalance = result.balance
            lastFullShieldedSyncAt = Date()
        }
        // Install the completion subscription before awaiting the initial
        // worker-context read. `await` yields the main actor, so doing the
        // initial read first could let a fast first shielded pass publish in
        // the gap between the seed check above and this subscription.
        shieldedEventCancellable = manager.$lastShieldedSyncEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                guard let self,
                      let result = event?.result(for: walletId),
                      result.success,
                      !result.cooldownSkip else { return }
                self.lastFullShieldedSyncAt = Date()
                self.handleShieldedBalanceResult(result, manager: manager)
                Task { @MainActor in
                    await ShieldedTxLookup.shared.refresh(reason: "shielded-sync-completed")
                }
            }

        // Seed the shielded funding-tx → locked-amount map (for the home tx
        // list's "Shielded transfer" rows) from whatever is already
        // persisted. Each completed pass above refreshes it again — a new
        // "to Shielded" transfer's asset lock lands around the same time its
        // note shows up in the balance.
        await ShieldedTxLookup.shared.refresh(reason: "manager-subscribe")

        // A suspended app cannot run the SDK's 60-second timer. Force one pass
        // after returning to the foreground when the last real scan is no
        // longer fresh. This is what makes an external same-seed spend appear
        // without requiring a full process relaunch.
        shieldedForegroundCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self, weak manager] _ in
                guard let self, let manager else { return }
                self.refreshShieldedOnForeground(using: manager)
            }

        // Keep a low-overhead guard around the SDK's regular polling. Healthy
        // 60-second passes keep moving `lastFullShieldedSyncAt`, so this task
        // does no extra network work. If the loop stalls or repeatedly fails,
        // one forced pass is requested once the snapshot is 90 seconds old.
        shieldedFreshnessTask?.cancel()
        shieldedFreshnessTask = Task { [weak self, weak manager] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        nanoseconds: UInt64(
                            ShieldedSyncFreshnessPolicy.watchdogInterval * 1_000_000_000))
                } catch {
                    return
                }
                guard let self, let manager else { return }
                self.refreshShieldedIfStale(using: manager)
            }
        }
    }

    private func refreshShieldedOnForeground(using manager: PlatformWalletManager) {
        let shouldRefresh = ShieldedSyncFreshnessPolicy.shouldRefreshOnForeground(
            now: Date(),
            lastFullScanAt: lastFullShieldedSyncAt,
            monitoringStartedAt: shieldedMonitoringStartedAt,
            isSyncing: manager.shieldedSyncIsSyncing,
            refreshInFlight: shieldedRefreshTask != nil)
        guard shouldRefresh else { return }
        requestShieldedRefresh(using: manager, reason: "foreground")
    }

    private func refreshShieldedIfStale(using manager: PlatformWalletManager) {
        let shouldRefresh = ShieldedSyncFreshnessPolicy.shouldRefreshForWatchdog(
            now: Date(),
            lastFullScanAt: lastFullShieldedSyncAt,
            monitoringStartedAt: shieldedMonitoringStartedAt,
            isSyncing: manager.shieldedSyncIsSyncing,
            refreshInFlight: shieldedRefreshTask != nil)
        guard shouldRefresh else { return }
        requestShieldedRefresh(using: manager, reason: "stale watchdog")
    }

    func requestShieldedRefresh(
        using manager: PlatformWalletManager,
        reason: String
    ) {
        guard isRunning, walletManager === manager, shieldedRefreshTask == nil else { return }

        shieldedRefreshGeneration &+= 1
        let generation = shieldedRefreshGeneration
        Self.logger.info(
            "🛡️ SHIELD :: requesting forced sync (\(reason, privacy: .public))")

        shieldedRefreshTask = Task { [weak self, weak manager] in
            guard let manager else { return }
            do {
                try await manager.syncShieldedNow()
            } catch {
                let errorDescription = String(describing: error)
                Self.logger.warning(
                    "🛡️ SHIELD :: force failed (\(reason, privacy: .public)): \(errorDescription, privacy: .public)")
            }

            guard let self, self.shieldedRefreshGeneration == generation else { return }
            self.shieldedRefreshTask = nil
        }
    }

    /// Run an immediate post-spend readback. If the first pass observes spent
    /// inputs before their change output, `handleShieldedBalanceResult` starts
    /// a bounded retry sequence and keeps the last reliable balance visible.
    func refreshShieldedBalanceAfterSpend(using manager: PlatformWalletManager) {
        Task {
            do {
                try await manager.syncShieldedNow()
            } catch {
                Self.logger.warning(
                    "🛡️ SHIELD :: post-spend sync failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func handleShieldedBalanceResult(
        _ result: ShieldedWalletSyncResult,
        manager: PlatformWalletManager
    ) {
        latestObservedShieldedBalance = result.balance

        if isShieldedBalanceReconciling {
            guard result.balance > 0 else { return }
            finishShieldedBalanceReconciliation(with: result.balance)
            return
        }

        // A spend's nullifier and its change note can become visible in
        // separate Platform reads. Publishing the intermediate zero makes the
        // user's remaining funds appear to vanish. Hold the previous snapshot
        // only when this pass actually discovered newly-spent notes; ordinary
        // zero balances still publish immediately.
        if result.balance == 0, result.newlySpent > 0, shieldedBalance > 0 {
            isShieldedBalanceReconciling = true
            Self.logger.info(
                "🛡️ SHIELD :: holding transient zero after \(result.newlySpent, privacy: .public) newly-spent note(s)")
            scheduleShieldedBalanceReconciliation(using: manager)
            return
        }

        shieldedBalance = result.balance
    }

    private func scheduleShieldedBalanceReconciliation(using manager: PlatformWalletManager) {
        shieldedReconciliationTask?.cancel()
        shieldedReconciliationTask = Task { [weak self] in
            // The background loop sleeps for 60 seconds. These bounded kicks
            // cover the common Platform-indexing window without leaving a
            // legitimate fully-spent balance stale indefinitely.
            for delayNanos in [UInt64(4_000_000_000), 12_000_000_000, 24_000_000_000] {
                do {
                    try await Task.sleep(nanoseconds: delayNanos)
                } catch {
                    return
                }
                guard let self, self.isShieldedBalanceReconciling else { return }
                do {
                    try await manager.syncShieldedNow()
                } catch {
                    Self.logger.warning(
                        "🛡️ SHIELD :: reconciliation sync failed: \(String(describing: error), privacy: .public)")
                }
            }

            // Combine delivers the completion on the main run loop. Give that
            // delivery one turn before deciding the bounded retries are done.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, self.isShieldedBalanceReconciling else { return }
            Self.logger.info("🛡️ SHIELD :: reconciliation window ended with zero balance")
            self.finishShieldedBalanceReconciliation(
                with: self.latestObservedShieldedBalance)
        }
    }

    private func finishShieldedBalanceReconciliation(with balance: UInt64) {
        shieldedBalance = balance
        isShieldedBalanceReconciling = false
        shieldedReconciliationTask?.cancel()
        shieldedReconciliationTask = nil
    }

    private func handleSyncEvent(_ event: PlatformAddressSyncEvent, walletId: Data) {
        guard let result = event.result(for: walletId) else { return }

        if result.success {
            // A healthy address-sync pass says nothing about the address
            // wallet, which failed to resolve at start and stays broken.
            lastError = addressWalletStartupError
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
            // Observed-payment ledger: diff this snapshot against the
            // persisted baseline and record unattributed increases as
            // received activity for the home history.
            if let network = runningNetwork {
                PlatformAddressActivityRecorder.observe(
                    addresses: derivedAddresses,
                    walletId: walletId,
                    network: network,
                    container: container)
            }
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
            for (_, _, balance, _, _, _, _) in cached {
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

    private func resolvePlatformAccountAvailability(
        walletId: Data
    ) -> PlatformAccountAvailability {
        guard let container = SwiftDashSDKHost.shared.modelContainer else {
            return .unknown
        }

        var descriptor = FetchDescriptor<PersistentWallet>(
            predicate: #Predicate { $0.walletId == walletId })
        descriptor.fetchLimit = 1

        do {
            guard let walletRow = try container.mainContext.fetch(descriptor).first else {
                return PlatformAccountAvailabilityPolicy.resolve(
                    hasWalletRecord: false,
                    hasPlatformPaymentAccount: false)
            }
            return PlatformAccountAvailabilityPolicy.resolve(
                hasWalletRecord: true,
                hasPlatformPaymentAccount: walletRow.accounts.contains { $0.accountType == 14 })
        } catch {
            Self.logger.warning(
                "🛰️ PLATFORM-ADDR :: platform-account availability lookup failed: \(String(describing: error), privacy: .public)")
            return .unknown
        }
    }

    private func resolveCurrentNetwork() -> Network? {
        WalletEnvironment.network
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
        case noPlatformReceiveAddress
        case mnemonicUnavailable
        case keyDecodeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .coordinatorNotReady:
                return NSLocalizedString(
                    "Platform sync is not running. Open Sync Info → Platform Sync Status to start it.",
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
            case .noPlatformReceiveAddress:
                return NSLocalizedString(
                    "Could not resolve a destination Platform Payment address",
                    comment: "InternalTransfer")
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

// MARK: - Shielded funding-tx lookup

/// Maps an L1 funding-transaction id to the shielded amount it locked,
/// sourced entirely from the SDK's `PersistentAssetLock` store — never from
/// DashSync. Lets the (migration-era, still partly DashSync-driven)
/// transaction list relabel a "to Shielded" funding tx as a *Shielded
/// transfer* and show the real locked amount instead of the zero both
/// DashSync and the SDK's net-change view compute for a self-directed
/// Type-18 asset lock they can't model.
///
/// `PersistentAssetLock` rows are deliberately retained even after the lock
/// is consumed, precisely so a funding tx can be mapped back to its locked
/// amount (see `ManagedAssetLockManager.AssetLockStatus.consumed`). The
/// shielded variant is funding type 5
/// (`FundingType.assetLockShieldedAddressTopUp`).
///
/// Snapshot design: `refresh()` captures the active `ModelContainer` on the
/// main actor, then rebuilds an immutable `[txid: ShieldedLockInfo]` map
/// (amount + status + vout) in a private, worker-thread `ModelContext`.
/// `amountDuffs(forTxidHex:)` / `info(forTxidHex:)` read the finished map under
/// a lock, so the (possibly background) transaction-list builder in
/// `Transaction` never touches SwiftData. Refreshed by
/// `PlatformAddressSyncCoordinator` on wallet start and on each completed
/// shielded sync pass.
final class ShieldedTxLookup {
    static let shared = ShieldedTxLookup()

    /// Funding-type discriminant for `AssetLockShieldedAddressTopUp`
    /// (`ManagedAssetLockManager.FundingType.assetLockShieldedAddressTopUp`).
    private static let shieldedFundingType = 5

    /// `AssetLockAddressTopUp` — the Core → Platform address funding lock.
    private static let platformFundingType = 4

    /// Identity funding locks: 0 = IdentityRegistration, 1 = IdentityTopUp,
    /// 2 = IdentityTopUpNotBound, 3 = IdentityInvitation.
    private static let identityFundingTypes = 0...3

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.shielded-tx-lookup")

    /// Snapshot value for one shielded funding tx: the locked amount plus the
    /// asset lock's current status and funding output index. `statusRaw`
    /// distinguishes a still-pending/stuck shield (1…3 — Broadcast/IS/CL) from
    /// a consumed, successful one (4) and from a chain-final lock whose
    /// Platform-side consumption is unknown (5 — RecoveredFromChain, either
    /// reconstructed during restore or reconciled from an unauthenticated
    /// already-consumed report; neither pending nor done); `vout` + the txid
    /// form the outpoint a recovery resume needs.
    struct ShieldedLockInfo: Sendable {
        let amountDuffs: UInt64
        let statusRaw: Int
        let vout: UInt32
        /// 5 = shielded funding, 4 = platform address funding.
        let fundingTypeRaw: Int
    }

    /// Value-only result crossing from the detached SwiftData reader back to
    /// the main actor. Persistent models and `ModelContext` never cross that
    /// boundary.
    private struct SnapshotBuildResult: Sendable {
        let map: [String: ShieldedLockInfo]?
        let assetLockCount: Int
        let typesSeen: [Int]
        let uncoveredTxids: [String]
        let errorDescription: String?
        let workerRanOffMain: Bool
    }

    private let lock = NSLock()
    /// txid (display-order hex, lowercased) → locked amount + status + vout.
    private var infoByTxid: [String: ShieldedLockInfo] = [:]

    /// Main-actor generation prevents a slow read from an old container (or
    /// an earlier refresh of the same container) from replacing newer state.
    @MainActor private var refreshGeneration: UInt64 = 0

    private init() {}

    /// Locked shielded amount (duffs) for an L1 funding txid, or `nil` if the
    /// txid is not a tracked shielded asset lock. `txidHex` must be
    /// display-order hex (reversed wire bytes), matching the txid component
    /// of `PersistentAssetLock.outPointHex`. Thread-safe; touches no SwiftData.
    func amountDuffs(forTxidHex txidHex: String) -> UInt64? {
        info(forTxidHex: txidHex)?.amountDuffs
    }

    /// Full snapshot entry (locked amount + asset-lock status + funding vout)
    /// for an L1 funding txid, or `nil` if the txid is not a tracked shielded
    /// asset lock. `txidHex` must be display-order hex (reversed wire bytes),
    /// matching the txid component of `PersistentAssetLock.outPointHex`.
    /// Thread-safe; touches no SwiftData.
    func info(forTxidHex txidHex: String) -> ShieldedLockInfo? {
        entry(forTxidHex: txidHex, fundingType: Self.shieldedFundingType)
    }

    /// Same snapshot entry for a Core → Platform (type 4) address-funding
    /// lock — powers the "Platform transfer" rows the way `info` powers the
    /// shielded ones. Thread-safe; touches no SwiftData.
    func platformFundingInfo(forTxidHex txidHex: String) -> ShieldedLockInfo? {
        entry(forTxidHex: txidHex, fundingType: Self.platformFundingType)
    }

    /// Snapshot entry for an identity funding lock (types 0…3 — registration,
    /// top-up, invitation). `fundingTypeRaw` distinguishes the variants.
    /// Thread-safe; touches no SwiftData.
    func identityFundingInfo(forTxidHex txidHex: String) -> ShieldedLockInfo? {
        let key = txidHex.lowercased()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = infoByTxid[key],
              Self.identityFundingTypes.contains(entry.fundingTypeRaw) else { return nil }
        return entry
    }

    /// The whole snapshot as (display-order hex txid, info) pairs. The caller
    /// owns the policy of which entries mean anything — this is the raw
    /// tracked set. Thread-safe; touches no SwiftData.
    func allEntries() -> [(txidHex: String, info: ShieldedLockInfo)] {
        lock.lock()
        defer { lock.unlock() }
        return infoByTxid.map { (txidHex: $0.key, info: $0.value) }
    }

    private func entry(forTxidHex txidHex: String, fundingType: Int) -> ShieldedLockInfo? {
        let key = txidHex.lowercased()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = infoByTxid[key], entry.fundingTypeRaw == fundingType else { return nil }
        return entry
    }

    /// Rebuild the snapshot from the active container's shielded asset-lock
    /// rows. Only container capture and final publication run on the main
    /// actor; all SQLite reads use a private `ModelContext` in a detached task.
    /// A nil container (no wallet running) clears the snapshot; a transient
    /// fetch error leaves the previous one in place.
    @MainActor
    func refresh(reason: String = "explicit") async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let refreshID = String(UUID().uuidString.prefix(8))

        guard let container = SwiftDashSDKHost.shared.modelContainer else {
            store([:])
            DWLogger.log(
                "🛡️ SHIELD-TX-REFRESH [\(refreshID)] skipped reason=\(reason) — no model container")
            return
        }

        let started = CFAbsoluteTimeGetCurrent()
        DWLogger.log(
            "🛡️ SHIELD-TX-REFRESH [\(refreshID)] start reason=\(reason) generation=\(generation)")

        let result = await Task.detached(priority: .utility) {
            Self.buildSnapshot(in: container)
        }.value
        let elapsedMS = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)

        guard generation == refreshGeneration,
              SwiftDashSDKHost.shared.modelContainer === container else {
            DWLogger.log(
                "🛡️ SHIELD-TX-REFRESH [\(refreshID)] stale after \(elapsedMS)ms reason=\(reason) offMain=\(result.workerRanOffMain)")
            return
        }

        if let errorDescription = result.errorDescription {
            Self.logger.error(
                "🛡️ SHIELD-TX :: refresh failed: \(errorDescription, privacy: .public)")
            DWLogger.log(
                "🛡️ SHIELD-TX-REFRESH [\(refreshID)] failed in \(elapsedMS)ms reason=\(reason) offMain=\(result.workerRanOffMain): \(errorDescription)")
            return
        }

        guard let map = result.map else { return }
        store(map)
        Self.logger.info(
            "🛡️ SHIELD-TX :: snapshot \(map.count, privacy: .public) funding tx(s) (shielded + platform)")
        DWLogger.log(
            "🛡️ SHIELD-TX-REFRESH [\(refreshID)] finish in \(elapsedMS)ms reason=\(reason) offMain=\(result.workerRanOffMain) rows=\(result.assetLockCount) snapshot=\(map.count) uncovered=\(result.uncoveredTxids.count)")

        if !result.uncoveredTxids.isEmpty {
            Self.logger.error(
                "🛡️ SHIELD-TX :: \(result.uncoveredTxids.count, privacy: .public) asset-lock tx(s) have no PersistentAssetLock row (SDK reconstruction gap?): \(result.uncoveredTxids.joined(separator: ","), privacy: .public)")
        }
        // Diagnostic: if asset locks exist but none matched the shielded
        // funding type, surface the types actually present so a single test
        // run reveals whether the discriminant assumption is wrong.
        if map.isEmpty && result.assetLockCount > 0 {
            Self.logger.info(
                "🛡️ SHIELD-TX :: \(result.assetLockCount, privacy: .public) asset lock(s) present, none funding-type \(Self.shieldedFundingType, privacy: .public); types=\(result.typesSeen, privacy: .public)")
        }
    }

    /// Worker-thread SwiftData pass. Asset locks are a tiny table; fetch all
    /// and filter in Swift rather than fighting `#Predicate` local-capture
    /// rules. The coverage query preserves the former launch diagnostic while
    /// keeping its SQLite work off the main actor as well.
    private static func buildSnapshot(in container: ModelContainer) -> SnapshotBuildResult {
        let workerRanOffMain = !Thread.isMainThread
        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let rows = try context.fetch(FetchDescriptor<PersistentAssetLock>())
            var map: [String: ShieldedLockInfo] = [:]
            let trackedTypes = Array(identityFundingTypes) + [platformFundingType, shieldedFundingType]
            for row in rows where trackedTypes.contains(row.fundingTypeRaw) && row.amountDuffs > 0 {
                // outPointHex == "<txid display hex>:<vout>"; key on the txid,
                // parse the vout after the colon. If one recurs, prefer the
                // most informative status: consumed (4) over recovered (5)
                // over the live pending window (0…3).
                guard let colon = row.outPointHex.firstIndex(of: ":") else { continue }
                let txid = row.outPointHex[..<colon].lowercased()
                guard let vout = UInt32(row.outPointHex[row.outPointHex.index(after: colon)...]) else { continue }
                let info = ShieldedLockInfo(
                    amountDuffs: UInt64(row.amountDuffs),
                    statusRaw: row.statusRaw,
                    vout: vout,
                    fundingTypeRaw: row.fundingTypeRaw)
                func rank(_ statusRaw: Int) -> Int { statusRaw == 4 ? .max : statusRaw }
                if let existing = map[txid], rank(existing.statusRaw) >= rank(info.statusRaw) { continue }
                map[txid] = info
            }

            // Coverage diagnostic. Every wallet-own asset-lock funding tx is
            // expected to have a store row; uncovered rows indicate an SDK
            // reconstruction gap and render as "Internal Transfer — 0 DASH".
            let assetLockKind = TransactionTypeKind.assetLock.rawValue
            let descriptor = FetchDescriptor<PersistentTransaction>(
                predicate: #Predicate { $0.transactionTypeKind == assetLockKind })
            let coveredTxids = Set(map.keys)
            let uncoveredTxids = try context.fetch(descriptor)
                .map { Transaction.displayHex($0.txid).lowercased() }
                .filter { !coveredTxids.contains($0) }

            return SnapshotBuildResult(
                map: map,
                assetLockCount: rows.count,
                typesSeen: Set(rows.map { $0.fundingTypeRaw }).sorted(),
                uncoveredTxids: uncoveredTxids,
                errorDescription: nil,
                workerRanOffMain: workerRanOffMain)
        } catch {
            return SnapshotBuildResult(
                map: nil,
                assetLockCount: 0,
                typesSeen: [],
                uncoveredTxids: [],
                errorDescription: String(describing: error),
                workerRanOffMain: workerRanOffMain)
        }
    }

    private func store(_ map: [String: ShieldedLockInfo]) {
        lock.lock()
        infoByTxid = map
        lock.unlock()
    }
}

// MARK: - DerivedPlatformAddress selection

extension Array where Element == DerivedPlatformAddress {
    /// The wallet's own next receive address: lowest-indexed unused address,
    /// falling back to the lowest-indexed overall. Single shared
    /// implementation for the Receive screen, the unshield destination, and
    /// Core → Platform funding.
    var nextReceiveAddress: DerivedPlatformAddress? {
        if let unused = filter({ !$0.isUsed })
            .min(by: { ($0.accountIndex, $0.addressIndex) < ($1.accountIndex, $1.addressIndex) }) {
            return unused
        }
        return self.min(by: { ($0.accountIndex, $0.addressIndex) < ($1.accountIndex, $1.addressIndex) })
    }
}
