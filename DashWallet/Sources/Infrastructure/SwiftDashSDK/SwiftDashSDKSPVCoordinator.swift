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
    /// Peers the SPV client is currently connected to, classified against
    /// the masternode list (Evonode / Masternode / Normal, or Unknown while
    /// the masternode phase hasn't synced).
    @Published public private(set) var connectedPeers: [PlatformSpvPeerInfo] = []

    // MARK: - Internal state

    private var runningNetwork: Network?
    private var progressCancellable: AnyCancellable?
    private var peersCancellable: AnyCancellable?
    private var balanceRefreshCancellable: AnyCancellable?

    /// Network whose CoinJoin gap was widened for a one-time recovery scan
    /// during the current run, so a subsequent full sync can mark recovery
    /// complete when nothing remains to recover. `nil` when no widen is active.
    private var coinJoinRecoveryWidenedNetwork: Network?

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

        // One-time wide CoinJoin recovery scan: on the first launch (per
        // network) of every wallet, widen the CoinJoin address gap (matching
        // DashSync) and pre-generate the addresses BEFORE startSpv, so the
        // initial filter already covers the full window and scattered mixed
        // coins are found. Reverts to the default gap once the scan completes
        // (a near-empty one-time scan for wallets that never used CoinJoin).
        applyCoinJoinRecoveryGapIfNeeded(for: network)

        // Pending birth-height chain resync: with the store deleted BEFORE
        // startSpv, the client re-anchors at the restored (lowered) birth
        // height and the armed rescan walks the recovered range. Must also
        // run before startSpv so the delete never races the sync loop's
        // segment writes. See `SPVChainResyncMarker` for why this only
        // happens on the launch after the marker was armed.
        let appliedChainResync = applyPendingChainResyncIfNeeded(
            for: network, dataDir: dataDir, manager: manager)

        do {
            try manager.startSpv(config: config)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: startSpv failed: \(String(describing: error), privacy: .public)")
            return .failure(StartError.spvClient(error))
        }

        // The resync marker survives a failed startSpv (the store is empty
        // either way; the next launch simply re-applies), and is consumed
        // only once the resynced client is actually running.
        if appliedChainResync {
            SPVChainResyncMarker.clear(for: network)
            Self.logger.info("🛰️ SPVCOORD :: chain resync applied on \(network.rawValue, privacy: .public)")
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
        peersCancellable?.cancel()
        peersCancellable = nil
        balanceRefreshCancellable?.cancel()
        balanceRefreshCancellable = nil

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
        coinJoinRecoveryWidenedNetwork = nil
        resetPublishedState()
        if let lastError {
            self.lastError = lastError
        }
    }

    // MARK: - CoinJoin recovery (one-time wide gap)

    /// Widen the CoinJoin address gap limit for the one-time recovery scan —
    /// applied on the first launch per network for every wallet, until the
    /// recovery flag is set (see `CoinJoinRecovery`). Must run BEFORE `startSpv`
    /// so the initial filter covers the wide window. No-op once recovered.
    /// Best-effort: a failure is logged and leaves the flag unset to retry next
    /// launch.
    @MainActor
    private func applyCoinJoinRecoveryGapIfNeeded(for network: Network) {
        coinJoinRecoveryWidenedNetwork = nil
        guard CoinJoinRecovery.shared.needsWideRecoveryGap(for: network) else { return }

        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.warning("🛰️ SPVCOORD :: coinjoin recovery: wallet not bound — skipping gap widen")
            return
        }

        do {
            // Widen the CoinJoin account's gap limit so the SPV scan re-discovers
            // mixed coins scattered beyond the default gap on BOTH the external
            // `/0/` and internal `/1/` pools. Core clamps to [1, MAX_GAP_LIMIT].
            try wallet.coreWallet().setGapLimit(
                accountType: .coinJoin,
                accountIndex: 0,
                gapLimit: CoinJoinRecovery.recoveryGapLimit)
            coinJoinRecoveryWidenedNetwork = network
            Self.logger.info(
                "🛰️ SPVCOORD :: CJTEST coinjoin recovery gap widened on \(network.rawValue, privacy: .public) to \(CoinJoinRecovery.recoveryGapLimit, privacy: .public)")
        } catch {
            Self.logger.error(
                "🛰️ SPVCOORD :: coinjoin recovery widen failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Pending chain resync application

    /// Apply a pending birth-height chain resync (see `SPVChainResyncMarker`):
    /// delete the network's SPV store so the upcoming `startSpv` re-anchors at
    /// the restored birth height, and rewind the wallet's live filter
    /// checkpoint to the marker height. The rewind is belt-and-suspenders for
    /// the arming session having re-raised the persisted `syncedHeight` after
    /// the arm (the arming save already rewound the row, which normally feeds
    /// the restore); a rewind failure is logged but doesn't retain the marker.
    ///
    /// Returns true when applied — the caller clears the marker once
    /// `startSpv` succeeds. Returns false (marker retained) when there is
    /// nothing pending, the marker was armed by this process (it must wait
    /// for a launch that restores the lowered birth height into Rust), or
    /// the store delete failed (retried next launch).
    @MainActor
    private func applyPendingChainResyncIfNeeded(
        for network: Network,
        dataDir: String,
        manager: PlatformWalletManager
    ) -> Bool {
        guard let pending = SPVChainResyncMarker.pending(for: network) else { return false }
        guard !pending.armedByThisSession else {
            Self.logger.info("🛰️ SPVCOORD :: chain resync armed this session — deferred to next launch")
            return false
        }

        let dir = URL(fileURLWithPath: dataDir, isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.removeItem(at: dir)
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: chain resync store delete failed: \(String(describing: error), privacy: .public)")
            return false
        }

        do {
            try manager.spvRescanFilters(walletId: pending.walletId, fromHeight: pending.fromHeight)
        } catch {
            // The wallet may have been wiped since arming (nothing left to
            // rescan; the store delete was the safe direction regardless).
            Self.logger.error("🛰️ SPVCOORD :: chain resync rescan arm failed: \(String(describing: error), privacy: .public)")
        }

        Self.logger.info("🛰️ SPVCOORD :: chain store cleared for resync from height \(pending.fromHeight, privacy: .public)")
        return true
    }

    /// After a widened recovery scan reaches `.synced`, mark recovery complete
    /// so future launches revert to the fast default gap. One completed wide
    /// scan is sufficient: the deep CoinJoin (4') UTXOs it discovered — and
    /// their address metadata — are persisted and reload on every later launch
    /// independently of the gap limit, so re-widening would only re-find the
    /// same coins. An interrupted scan never reaches `.synced`, so it safely
    /// retries next launch. (Sweeping is the user's separate choice and no
    /// longer drives re-scanning.)
    @MainActor
    private func maybeCompleteCoinJoinRecovery(state: SPVSyncState) {
        guard state == .synced,
              let network = coinJoinRecoveryWidenedNetwork,
              network == runningNetwork else { return }

        Self.logger.info("🛰️ SPVCOORD :: CJTEST coinjoin recovery scan reached .synced on \(network.rawValue, privacy: .public) — marking recovered")
        CoinJoinRecovery.shared.markRecovered(for: network)
        coinJoinRecoveryWidenedNetwork = nil
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
        peersCancellable = manager.$spvPeers
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in
                MainActor.assumeIsolated {
                    self?.connectedPeers = peers
                }
            }

        // Refresh the published balance whenever Rust's persister commits a
        // SwiftData batch (a detected/instant-locked tx writes PersistentTransaction
        // rows → NSManagedObjectContextDidSave). The progress-tick refresh above
        // stops firing once the chain is fully synced (steady state has no ticks),
        // so an incoming payment while synced would otherwise not update the balance
        // until the next foreground/restart. This is the same trigger the home tx
        // list already uses; throttled to coalesce the save storm during sync.
        balanceRefreshCancellable = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave)
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshBalanceBridge()
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

        // Once a wide recovery scan has fully synced, revert to the fast gap if
        // there's nothing (left) to recover. Runs after the balance refresh so
        // `coinJoinBalanceDuffs` reflects the completed scan.
        maybeCompleteCoinJoinRecovery(state: mappedState)
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
        connectedPeers = []
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

// MARK: - Pending chain resync (birth-height repair)

/// One-shot "clear the SPV chain store and rescan at the next launch"
/// marker, armed by the SPV Status screen when a wallet's birth height is
/// lowered and applied by `SwiftDashSDKSPVCoordinator.performStart`.
///
/// Why a next-launch marker instead of acting immediately: the running Rust
/// wallet's birth height is fed once from `PersistentWallet` when wallets
/// load and has no update FFI, and dash-spv never re-anchors an existing
/// header store (`initialize_genesis_block` returns early when any headers
/// exist). A lowered birth height can therefore only take effect on a launch
/// whose SPV start finds an EMPTY store: the client then anchors at the
/// freshly restored birth height and the filter scan can reach the recovered
/// range. Applying the marker in the session that armed it would delete the
/// store and immediately re-anchor at the stale in-memory birth height,
/// consuming the marker without repairing anything — hence the session guard.
///
/// UserDefaults-backed, per network, one wallet at a time (the repair is a
/// single-wallet diagnostic; arming again overwrites). Follows the
/// `CoinJoinRecovery` pre-start maintenance-flag pattern; lives in this file
/// because `performStart` is its consumer and the SPV Status screen its only
/// producer.
enum SPVChainResyncMarker {

    private static let logger = Logger(
        subsystem: "org.dashfoundation.dash",
        category: "swift-sdk-migration.spv-chain-resync")

    /// Stable for the lifetime of this process. A marker armed by this
    /// process is only applied by a later one (see type doc).
    private static let sessionId = UUID().uuidString

    struct Pending {
        let walletId: Data
        let fromHeight: UInt32
        let armedBySessionId: String

        var armedByThisSession: Bool { armedBySessionId == SPVChainResyncMarker.sessionId }
    }

    private static func key(for network: Network) -> String {
        "spvChainResync.v1.pending.\(network == .mainnet ? "mainnet" : "testnet")"
    }

    /// Arm the marker: `network`'s chain store is deleted before the first
    /// `startSpv` of a later app session, and `walletId`'s filter checkpoint
    /// is rewound to `fromHeight`. Overwrites any pending marker for the
    /// network.
    static func arm(walletId: Data, fromHeight: UInt32, network: Network) {
        UserDefaults.standard.set(
            [
                "walletId": walletId.hexEncodedString(),
                "fromHeight": NSNumber(value: fromHeight),
                "sessionId": sessionId,
            ] as [String: Any],
            forKey: key(for: network))
        logger.info("🛰️ SPV-RESYNC :: armed for \(network.rawValue, privacy: .public) from height \(fromHeight, privacy: .public)")
    }

    /// Drop a pending marker for `walletId` (e.g. the birth height was
    /// raised again before the resync ran, superseding it). No-op when the
    /// pending marker belongs to a different wallet.
    static func disarm(walletId: Data, network: Network) {
        guard let p = pending(for: network), p.walletId == walletId else { return }
        clear(for: network)
        logger.info("🛰️ SPV-RESYNC :: disarmed for \(network.rawValue, privacy: .public)")
    }

    static func pending(for network: Network) -> Pending? {
        guard let dict = UserDefaults.standard.dictionary(forKey: key(for: network)),
              let walletIdHex = dict["walletId"] as? String,
              let walletId = Data(hexString: walletIdHex),
              let fromHeight = (dict["fromHeight"] as? NSNumber)?.uint32Value,
              let armedBySessionId = dict["sessionId"] as? String else {
            return nil
        }
        return Pending(
            walletId: walletId,
            fromHeight: fromHeight,
            armedBySessionId: armedBySessionId)
    }

    static func clear(for network: Network) {
        UserDefaults.standard.removeObject(forKey: key(for: network))
    }

    /// Clear pending markers on a wallet wipe: the rows and chain data they
    /// reference are gone, so a stale marker would only wipe the next
    /// wallet's fresh sync. Clears both networks, mirroring
    /// `CoinJoinRecovery.resetForWipe`.
    static func resetForWipe() {
        clear(for: .mainnet)
        clear(for: .testnet)
    }
}
