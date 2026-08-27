//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation
import SwiftDashSDK

private let kMaxProgressDelta = 0.1 // 10%

// Wait for 2.5 seconds to update progress to the new peak value.
// Peak is considered to be a difference between progress values more than 10%.
private let kProgressPeakDelay: TimeInterval = 3.25 // 3.25 sec

private let kSyncStateChangedNewStateKey = "DWSyncStateChangedNewStateKey"
private let kSyncStateChangedFromStateKey = "DWSyncStateChangedFromStateKey"

// MARK: - SyncStateSnapshot

/// SwiftDashSDK-backed replacement for the `DSSyncState` model that
/// `SyncingActivityMonitor.model` used to expose. Holds the per-phase
/// progress fields the syncing UI needs ("header #x of y", "block #x of y",
/// "masternode list #x of y") in a form decoupled from DashSync. Populated
/// by `SyncingActivityMonitor` from `SwiftDashSDKSPVCoordinator.shared.syncProgress`.
@objc
public class SyncStateSnapshot: NSObject {
    @objc(SyncStateKind)
    public enum Kind: Int {
        case offline       // not started / no peers
        case headers       // syncing block headers
        case filterHeaders
        case filters
        case blocks        // syncing full blocks
        case masternodes
        case finished
    }

    /// One row of per-phase sync detail for UI that shows the WHOLE sync
    /// pipeline (headers → filter headers → filters → masternode lists)
    /// instead of only the currently-active phase. Swift-only — the Obj-C
    /// consumers of the snapshot never needed per-phase rows.
    public struct Phase {
        public enum Kind {
            case headers
            case filterHeaders
            case filters
            case masternodes
        }

        public let kind: Kind
        public let current: UInt32
        public let target: UInt32
        /// True when dash-spv reports the phase caught up (headers/filter
        /// phases: percentage ≥ 1; masternodes: target height reached).
        public let isComplete: Bool
    }

    @objc public let kind: Kind
    @objc public let lastSyncBlockHeight: UInt32
    @objc public let lastTerminalBlockHeight: UInt32
    @objc public let estimatedBlockHeight: UInt32
    @objc public let masternodeListsReceived: UInt32
    @objc public let masternodeListsTotal: UInt32
    /// All phases dash-spv has reported so far, in pipeline order. Empty
    /// until the first SDK progress event lands.
    public let phases: [Phase]

    init(kind: Kind,
         lastSyncBlockHeight: UInt32,
         lastTerminalBlockHeight: UInt32,
         estimatedBlockHeight: UInt32,
         masternodeListsReceived: UInt32,
         masternodeListsTotal: UInt32,
         phases: [Phase] = []) {
        self.kind = kind
        self.lastSyncBlockHeight = lastSyncBlockHeight
        self.lastTerminalBlockHeight = lastTerminalBlockHeight
        self.estimatedBlockHeight = estimatedBlockHeight
        self.masternodeListsReceived = masternodeListsReceived
        self.masternodeListsTotal = masternodeListsTotal
        self.phases = phases
        super.init()
    }

    static let empty = SyncStateSnapshot(
        kind: .offline,
        lastSyncBlockHeight: 0,
        lastTerminalBlockHeight: 0,
        estimatedBlockHeight: 0,
        masternodeListsReceived: 0,
        masternodeListsTotal: 0)
}

// MARK: - SyncingActivityMonitorObserver

@objc
protocol SyncingActivityMonitorObserver: AnyObject {
    func syncingActivityMonitorProgressDidChange(_ progress: Double)
    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State)
}

// MARK: - SyncingActivityMonitor

@objc
class SyncingActivityMonitor: NSObject, NetworkReachabilityHandling {
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    var reachabilityObserver: Any!

    @objc(SyncingActivityMonitorState)
    enum State: Int {
        case syncing
        case syncDone
        case syncFailed
        case noConnection
        case unknown
    }

    /// Latest per-phase sync snapshot, populated from
    /// `SwiftDashSDKSPVCoordinator.shared.syncProgress`. Replaces the
    /// previous DashSync `model: DSSyncState` property.
    @objc public private(set) var snapshot: SyncStateSnapshot = .empty

    @objc
    public var progress: Double = 0 {
        didSet {
            observerSnapshot().forEach { $0.syncingActivityMonitorProgressDidChange(progress) }
        }
    }

    @objc
    public var state: State = .unknown {
        didSet {
            if state == .syncDone {
                DWGlobalOptions.sharedInstance().isResyncingWallet = false
            }

            guard oldValue != state else {
                return
            }

            NotificationCenter.default.post(name: .syncStateChangedNotification, object: nil,
                                            userInfo: [
                                                kSyncStateChangedFromStateKey: oldValue,
                                                kSyncStateChangedNewStateKey: state,
                                            ])

            observerSnapshot().forEach { $0.syncingActivityMonitorStateDidChange(previousState: oldValue, state: state) }
        }
    }

    private var isSyncing = false {
        didSet {
            // All writers reach this on the main thread (Combine pipeline
            // `.receive(on: RunLoop.main)`, reachability callback hops via
            // `Task { @MainActor in }`). `assumeIsolated` asserts that at
            // runtime and gives Xcode's Main-Thread-Checker heuristic the
            // isolation proof it won't accept from `DispatchQueue.main.async`
            // or a detached `Task { @MainActor in }`.
            MainActor.assumeIsolated {
                UIApplication.shared.isIdleTimerDisabled = isSyncing
            }
        }
    }

    private var lastPeakDate: Date?
    private var cancellables = Set<AnyCancellable>()

    private var observers: [SyncingActivityMonitorObserver] = []
    private let observersLock = NSLock()

    override init() {
        super.init()

        initializeReachibility()
        subscribeToCoordinator()
    }

    @objc
    public func forceStartSyncingActivity() {
        // Idempotent on the active network — runtime avoids a full restart
        // when SwiftDashSDK is already running for the current chain.
        SwiftDashSDKWalletRuntime.startIfReady()
    }

    @objc(addObserver:)
    public func add(observer: SyncingActivityMonitorObserver) {
        observersLock.lock()
        defer { observersLock.unlock() }
        observers.append(observer)
    }

    @objc(removeObserver:)
    public func remove(observer: SyncingActivityMonitorObserver) {
        observersLock.lock()
        defer { observersLock.unlock() }
        if let idx = observers.firstIndex(where: { $0 === observer }) {
            observers.remove(at: idx)
        }
    }

    private func observerSnapshot() -> [SyncingActivityMonitorObserver] {
        observersLock.lock()
        defer { observersLock.unlock() }
        return observers
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let observer = reachabilityObserver {
            NotificationCenter.default.removeObserver(observer)
            reachabilityObserver = nil
        }
    }

    /// ObjC-visible accessor for `.syncStateChangedNotification` (same
    /// pattern as `DWSwiftDashSDKWalletState.balanceDidChangeNotification`).
    @objc public static let syncStateChangedNotificationName = Notification.Name.syncStateChangedNotification

    @objc public static let shared = SyncingActivityMonitor()
}

// MARK: - SwiftDashSDK coordinator subscription

extension SyncingActivityMonitor {
    /// Subscribe to `SwiftDashSDKSPVCoordinator.shared`'s @Published streams.
    /// We `combineLatest` the four pieces of state we care about so the
    /// downstream sink always sees a coherent tuple. The coordinator already
    /// marshals its publishes to the main queue, so the `.receive(on:)` here
    /// is belt-and-suspenders.
    private func subscribeToCoordinator() {
        let coord = SwiftDashSDKSPVCoordinator.shared

        coord.$state
            .combineLatest(coord.$progress, coord.$syncProgress, coord.$bestPeerHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] sdkState, sdkProgress, sdkSyncProgress, peersBest in
                self?.handleCoordinatorUpdate(
                    sdkState: sdkState,
                    sdkProgress: sdkProgress,
                    sdkSyncProgress: sdkSyncProgress,
                    peersBestHeight: peersBest)
            }
            .store(in: &cancellables)
    }

    private func handleCoordinatorUpdate(
        sdkState: SPVSyncState,
        sdkProgress: Double,
        sdkSyncProgress: SPVSyncProgress,
        peersBestHeight: UInt32
    ) {
        // Refresh the snapshot consumers read in their UI tick.
        snapshot = makeSnapshot(from: sdkSyncProgress, peersBestHeight: peersBestHeight)

        // Reachability gate stays the same — overrides everything else.
        if reachability.networkStatus == .offline {
            applyProgressWithPeakSmoothing(sdkProgress)
            isSyncing = false
            state = .noConnection
            return
        }

        // Map SPVSyncState → SyncingActivityMonitor.State.
        let mapped: State
        switch sdkState {
        case .synced:
            mapped = .syncDone
        case .error:
            mapped = .syncFailed
        case .syncing:
            mapped = .syncing
        case .waitForEvents:
            // dash-spv's steady state for a fully-synced client: sub-managers
            // drop from Synced to WaitForEvents once they switch to listening
            // for new blocks, so the overall Synced state is only a transient
            // window (progress.rs — overall is Synced only while ALL managers
            // are simultaneously Synced). WaitForEvents is also the pre-start
            // default, so disambiguate on progress: fully caught up → done.
            if sdkProgress >= 0.999 {
                mapped = .syncDone
            } else {
                mapped = (state == .syncing) ? .syncing : .unknown
            }
        case .waitingForConnections, .idle:
            // Pre-sync states — hold .syncing if we were already syncing,
            // otherwise show .unknown so the UI doesn't flash.
            mapped = (state == .syncing) ? .syncing : .unknown
        case .unknown:
            mapped = .unknown
        }

        applyProgressWithPeakSmoothing(sdkProgress)
        isSyncing = (mapped == .syncing)
        state = mapped
    }

    /// Map SwiftDashSDK's per-phase progress to the snapshot fields the
    /// existing UI consumers expect. The phase priority order
    /// (headers → filterHeaders → filters → masternodes → finished)
    /// matches what dashwallet's syncing UI used to render under DashSync.
    private func makeSnapshot(
        from progress: SPVSyncProgress,
        peersBestHeight: UInt32
    ) -> SyncStateSnapshot {
        let kind: SyncStateSnapshot.Kind
        if progress.state.isComplete() {
            kind = .finished
        } else if let h = progress.headers, h.percentage < 1.0 {
            kind = .headers
        } else if let fh = progress.filterHeaders, fh.percentage < 1.0 {
            kind = .filterHeaders
        } else if let f = progress.filters, f.percentage < 1.0 {
            kind = .filters
        } else if let m = progress.masternodes, m.targetHeight > m.currentHeight {
            kind = .masternodes
        } else {
            kind = .offline
        }

        let headerHeight = progress.headers?.currentHeight ?? 0
        let blockHeight = headerHeight
        let mnReceived = progress.masternodes?.diffsProcessed ?? 0
        // SDK doesn't expose "total masternode lists to download" directly;
        // approximate from the height delta on the masternodes phase. UI
        // uses this only for an "x of y" string.
        let mnTotal: UInt32 = {
            guard let m = progress.masternodes else { return 0 }
            return m.targetHeight > m.currentHeight ? (m.targetHeight - m.currentHeight) : 0
        }()

        // Per-phase rows in pipeline order, one per phase dash-spv has
        // reported. The syncing detail alert shows all of them so a user
        // isn't left staring at "header #x of x" while the filter phases
        // are what the overall percentage is actually grinding through.
        var phases: [SyncStateSnapshot.Phase] = []
        if let h = progress.headers {
            phases.append(.init(kind: .headers,
                                current: h.currentHeight,
                                target: h.targetHeight,
                                isComplete: h.percentage >= 1.0))
        }
        if let fh = progress.filterHeaders {
            phases.append(.init(kind: .filterHeaders,
                                current: fh.currentHeight,
                                target: fh.targetHeight,
                                isComplete: fh.percentage >= 1.0))
        }
        if let f = progress.filters {
            phases.append(.init(kind: .filters,
                                current: f.currentHeight,
                                target: f.targetHeight,
                                isComplete: f.percentage >= 1.0))
        }
        if let m = progress.masternodes {
            phases.append(.init(kind: .masternodes,
                                current: m.currentHeight,
                                target: m.targetHeight,
                                isComplete: m.targetHeight <= m.currentHeight))
        }

        return SyncStateSnapshot(
            kind: kind,
            lastSyncBlockHeight: blockHeight,
            lastTerminalBlockHeight: headerHeight,
            estimatedBlockHeight: peersBestHeight,
            masternodeListsReceived: mnReceived,
            masternodeListsTotal: mnTotal,
            phases: phases)
    }

    /// Smooth out large progress jumps for visual continuity. Mirrors the
    /// pre-M5 behaviour: only commit a new value to `self.progress` once
    /// the SDK has held the new peak for `kProgressPeakDelay` seconds, or
    /// when the delta is small enough that it's not a peak.
    private func applyProgressWithPeakSmoothing(_ newProgress: Double) {
        if fabs(self.progress - newProgress) > kMaxProgressDelta {
            if let date = lastPeakDate {
                if -date.timeIntervalSinceNow > kProgressPeakDelay {
                    lastPeakDate = nil
                }
            }
            else {
                lastPeakDate = Date()
            }
        }
        else {
            lastPeakDate = nil
        }

        if lastPeakDate == nil {
            self.progress = newProgress
        }
    }
}

// MARK: - Reachability

extension SyncingActivityMonitor {
    private func initializeReachibility() {
        networkStatusDidChange = { [weak self] _ in
            // Re-evaluate state when reachability flips by replaying the
            // current coordinator snapshot through `handleCoordinatorUpdate`.
            // The Combine pipeline doesn't fire on reachability changes, so
            // without this kick the .noConnection state would be sticky.
            //
            // Main-hop: `startNetworkMonitoring()` fires this synchronously
            // during init, so when the shared singleton is lazy-initialized
            // from a background Task (e.g. `CoinJoinService.restoreMode`),
            // `handleCoordinatorUpdate` would otherwise run off-main and
            // `isSyncing`'s `UIApplication.isIdleTimerDisabled` didSet would
            // trip the main-thread barrier.
            let apply: () -> Void = {
                guard let self else { return }
                let coord = SwiftDashSDKSPVCoordinator.shared
                self.handleCoordinatorUpdate(
                    sdkState: coord.state,
                    sdkProgress: coord.progress,
                    sdkSyncProgress: coord.syncProgress,
                    peersBestHeight: coord.bestPeerHeight)
            }
            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }
        startNetworkMonitoring()
    }
}

// MARK: - Notification name constants

extension Notification.Name {
    // The typed sync-state-change surface. Posted from `state`'s didSet with
    // the from/new states in userInfo; ObjC observers reach it through
    // `SyncingActivityMonitor.syncStateChangedNotificationName`.
    static let syncStateChangedNotification: Notification.Name = .init(rawValue: "DWSyncStateChangedNotification")
}
