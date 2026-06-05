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

    // MARK: - Internal state

    private var runningNetwork: Network?
    private var progressCancellable: AnyCancellable?

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

        do {
            try manager.startSpv(config: config)
        } catch {
            Self.logger.error("🛰️ SPVCOORD :: startSpv failed: \(String(describing: error), privacy: .public)")
            return .failure(StartError.spvClient(error))
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
            let highest = try wallet.coreWallet().setCoinJoinGapLimit(
                accountIndex: 0,
                gapLimit: CoinJoinRecovery.recoveryGapLimit)
            coinJoinRecoveryWidenedNetwork = network
            Self.logger.info(
                "🛰️ SPVCOORD :: coinjoin recovery gap widened to \(CoinJoinRecovery.recoveryGapLimit, privacy: .public) (highest idx \(highest, privacy: .public))")
        } catch {
            Self.logger.error(
                "🛰️ SPVCOORD :: coinjoin recovery widen failed: \(String(describing: error), privacy: .public)")
        }
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

        CoinJoinRecovery.shared.markRecovered(for: network)
        coinJoinRecoveryWidenedNetwork = nil
    }

    /// DEBUG / TEST ONLY (🧪 CJTEST). Unconditionally widen the CoinJoin
    /// address gap so freshly-funded CoinJoin (4') receive addresses up to
    /// `gapLimit` are watched this session — bypassing the `CoinJoinRecovery`
    /// detection flag. Used by the CoinJoin recovery debug console in Tools to
    /// simulate the post-migration recovery scan without real mixed coins.
    /// Remove together with that console before release (see the TODO in
    /// `CoinJoinRecovery.swift`).
    @MainActor
    @discardableResult
    func debugForceWidenCoinJoinGap(gapLimit: UInt32) -> UInt32? {
        guard let wallet = SwiftDashSDKHost.shared.wallet else {
            Self.logger.warning("🧪 CJTEST :: widen — wallet not bound")
            return nil
        }
        do {
            let highest = try wallet.coreWallet().setCoinJoinGapLimit(
                accountIndex: 0,
                gapLimit: gapLimit)
            Self.logger.info(
                "🧪 CJTEST :: forced coinjoin gap widen to \(gapLimit, privacy: .public) (highest idx \(highest, privacy: .public))")
            return highest
        } catch {
            Self.logger.error(
                "🧪 CJTEST :: widen failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// DEBUG / TEST ONLY (🧪 CJTEST). Force a FULL blockchain rescan with the
    /// CoinJoin gap widened, so HISTORICAL mixed coins are discovered:
    ///   1. widen the CoinJoin gap (so the rebuilt BIP158 filter covers CoinJoin
    ///      addresses), then
    ///   2. `clearSpvStorage()` on the RUNNING client — wipes persisted
    ///      headers/filters/sync-state; the live client then re-syncs the whole
    ///      chain from scratch, rebuilding the filter from the (widened) wallet
    ///      monitor.
    /// We deliberately do NOT stop/start the SPV: a stop tears down the peer
    /// connections and the fresh start hangs at `waitForEvents` (no peers,
    /// headers 0/0 — observed). Clearing on the live client keeps the peers
    /// connected so it re-downloads immediately. Keys / addresses / tx history
    /// live elsewhere and are untouched. Heavy: re-downloads the whole chain
    /// (minutes); the main balance dips then rebuilds. Remove with the debug
    /// console.
    @MainActor
    func debugFullRescanWithWidenedCoinJoinGap(gapLimit: UInt32) async {
        guard runningNetwork != nil else {
            Self.logger.warning("🧪 CJTEST :: rescan — SPV not running (no network)")
            return
        }
        guard let manager = SwiftDashSDKHost.shared.manager else {
            Self.logger.warning("🧪 CJTEST :: rescan — no manager bound")
            return
        }
        Self.logger.info(
            "🧪 CJTEST :: rescan START — tip before clear=\(self.tipHeight, privacy: .public) state=\(String(describing: self.state), privacy: .public)")

        _ = debugForceWidenCoinJoinGap(gapLimit: gapLimit)
        let afterWiden = debugBalanceSnapshot()
        Self.logger.info(
            "🧪 CJTEST :: after widen — CoinJoin pool keys=\(afterWiden.cjUsed, privacy: .public)/\(afterWiden.cjTotal, privacy: .public) (expect total≈\(gapLimit, privacy: .public))")

        do {
            try manager.clearSpvStorage()
            Self.logger.info(
                "🧪 CJTEST :: cleared SPV storage — live client re-syncs from scratch with the wide filter (peers stay connected, NO stop/start)")
        } catch {
            Self.logger.error(
                "🧪 CJTEST :: clearSpvStorage failed: \(String(describing: error), privacy: .public)")
            return
        }
        debugLogRescanProgress()
    }

    /// 🧪 CJTEST snapshot of the CoinJoin account (tag 1, idx 0) keys/balance and
    /// the BIP44 account (tag 0, idx 0) balance, read straight from the SDK's
    /// per-account balances. Remove with the debug console.
    @MainActor
    private func debugBalanceSnapshot() -> (cjBalance: UInt64, cjUsed: UInt32, cjTotal: UInt32, bip44: UInt64) {
        var cjBal: UInt64 = 0, cjUsed: UInt32 = 0, cjTotal: UInt32 = 0, bip44: UInt64 = 0
        if let manager = SwiftDashSDKHost.shared.manager, let wallet = SwiftDashSDKHost.shared.wallet {
            for e in manager.accountBalances(for: wallet.walletId) {
                if e.typeTag == 1 && e.index == 0 {
                    cjBal &+= e.confirmed &+ e.unconfirmed
                    cjUsed = e.keysUsed
                    cjTotal = e.keysTotal
                } else if e.typeTag == 0 && e.index == 0 {
                    bip44 &+= e.confirmed &+ e.unconfirmed
                }
            }
        }
        return (cjBal, cjUsed, cjTotal, bip44)
    }

    /// 🧪 CJTEST — poll + log the rescan progression every ~3s so the log tells
    /// the whole story: did headers/filters actually drop low and climb (= a
    /// real from-scratch rescan, vs. instantly 100% = resumed/no rescan), and
    /// did the CoinJoin balance/keys ever appear. Ends with a full account dump
    /// once synced, or after a cap. Remove with the debug console.
    @MainActor
    private func debugLogRescanProgress() {
        Task { @MainActor in
            let maxTicks = 80
            for tick in 0..<maxTicks {
                let p = self.syncProgress
                let h = p.headers
                let f = p.filters
                // Read ONLY published state here (no per-tick FFI) so the polling
                // can't contend with the SPV client during connect/sync bootstrap.
                let cj = SwiftDashSDKWalletState.shared.coinJoinBalanceDuffs
                let bip44 = SwiftDashSDKWalletState.shared.balance?.total ?? 0
                let line = "🧪 CJTEST :: rescan[\(tick)] \(String(describing: self.state)) \(Int(p.percentage))% | headers \(h?.currentHeight ?? 0)/\(h?.targetHeight ?? 0) filters \(f?.currentHeight ?? 0)/\(f?.targetHeight ?? 0) tip \(self.tipHeight)/\(self.bestPeerHeight) | CJ \(cj)d | BIP44 \(bip44)d"
                Self.logger.info("\(line, privacy: .public)")

                if self.state == .synced && tick >= 2 {
                    Self.logger.info("🧪 CJTEST :: rescan SYNCED — final account dump:")
                    for entry in SwiftDashSDKCoinJoinBalanceReader.debugDumpAllBalances() {
                        Self.logger.info("🧪 CJTEST ::    \(entry, privacy: .public)")
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            Self.logger.info("🧪 CJTEST :: rescan progress logging stopped (cap reached)")
        }
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
