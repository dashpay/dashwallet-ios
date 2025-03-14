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

import Foundation

private let kChainManagerNotificationChainKey = "DSChainManagerNotificationChainKey"
private let kChainManagerNotificationSyncStateKey = "DSChainManagerNotificationSyncStateKey"

private let kSyncingCompleteProgress = 1.0
private let kMaxProgressDelta = 0.1 // 10%

// Wait for 2.5 seconds to update progress to the new peak value.
// Peak is considered to be a difference between progress values more than 10%.
private let kProgressPeakDelay: TimeInterval = 3.25 // 3.25 sec
private let kSyncLoopInterval: TimeInterval = 0.2

private let kSyncStateChangedNewStateKey = "DWSyncStateChangedNewStateKey"
private let kSyncStateChangedFromStateKey = "DWSyncStateChangedFromStateKey"

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
    public lazy var model: DSSyncState = DSSyncState(syncPhase: .offline)

    @objc
    public var progress: Double = 0 {
        didSet {
            observers.forEach { $0.syncingActivityMonitorProgressDidChange(progress) }
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

            observers.forEach { $0.syncingActivityMonitorStateDidChange(previousState: oldValue, state: state) }
        }
    }

    private var isSyncing = false {
        didSet {
            UIApplication.shared.isIdleTimerDisabled = isSyncing
        }
    }

    private var lastPeakDate: Date?

    private lazy var observers: [SyncingActivityMonitorObserver] = []

    override init() {
        super.init()

        initializeReachibility()
        configureObserver()
        startSyncingIfNeeded()
    }

    @objc
    public func forceStartSyncingActivity() {
        startSyncingActivity()
    }

    @objc(addObserver:)
    public func add(observer: SyncingActivityMonitorObserver) {
        observers.append(observer)
    }

    @objc(removeObserver:)
    public func remove(observer: SyncingActivityMonitorObserver) {
        if let idx = observers.firstIndex(where: { $0 === observer }) {
            observers.remove(at: idx)
        }
    }

    // MARK: Notifications

    @objc
    func chainManagerSyncStartedNotification(notification: Notification) {
        guard shouldAcceptSyncNotification(notification) else { return }
        startSyncingActivity()
    }

    @objc
    func chainManagerSyncFinishedNotification(notification: Notification) {
        guard shouldAcceptSyncNotification(notification) else { return }
        guard shouldStopSyncing else { return }

        stopSyncingActivity(failed: false)
    }

    @objc
    func chainManagerSyncFailedNotification(notification: Notification) {
        guard shouldAcceptSyncNotification(notification) else { return }

        stopSyncingActivity(failed: true)
    }
    
    @objc
    func chainManagerSyncStateChangedNotification(notification: Notification) {
        guard shouldAcceptSyncNotification(notification) else { return }
        
        if let model = notification.userInfo?[kChainManagerNotificationSyncStateKey] as? DSSyncState {
            self.model = model
        }
    }
    
    @objc
    func peerManagerConnectedPeersDidChangeNotification(notification: Notification) {
       if model.peerManagerConnected {
            removeChainObserver(.peerManagerConnectedPeersDidChange)
            startSyncingIfNeeded()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.removeObserver(reachabilityObserver!)
    }

    @objc public static let shared = SyncingActivityMonitor()
}

// MARK: Syncing

extension SyncingActivityMonitor {
    
    private func startSyncingIfNeeded() {
        guard model.peerManagerConnected else {
            addChainObserver(.peerManagerConnectedPeersDidChange, #selector(peerManagerConnectedPeersDidChangeNotification(notification:)))
            return
        }

        startSyncingActivity()
    }

    private func startSyncingActivity() {
        guard !isSyncing else { return }

        progress = model.combinedSyncProgress
        lastPeakDate = nil

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(syncLoop), object: nil)
        syncLoop()
    }

    private func stopSyncingActivity(failed: Bool) {
        guard isSyncing else { return }

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(syncLoop), object: nil)

        isSyncing = false
        state = failed ? .syncFailed : .syncDone
    }
    
    @objc
    private func syncLoop() {
        guard reachability.networkReachabilityStatus != .notReachable else {
            state = .noConnection
            return
        }
        DispatchQueue.main.async {
            self.updateProgress()
        }
    }

    private func updateProgress() {
        let progress = model.combinedSyncProgress
        if progress < kSyncingCompleteProgress {
            isSyncing = true

            if fabs(self.progress - progress) > kMaxProgressDelta {
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
                self.progress = progress
            }

            state = .syncing

            perform(#selector(syncLoop), with: nil, afterDelay: kSyncLoopInterval)
        }
        else {
            stopSyncingActivity(failed: false)
        }
    }
}

// MARK: Private

extension SyncingActivityMonitor {
    private func initializeReachibility() {
        networkStatusDidChange = { [weak self] _ in
            self?.forceSyncLoop()
        }
        startNetworkMonitoring()
    }

    private func forceSyncLoop() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(syncLoop), object: nil)
        syncLoop()
    }

    private func addChainObserver(_ aName: NSNotification.Name?, _ aSelector: Selector) {
        NotificationCenter.default.addObserver(self, selector: aSelector, name: aName, object: nil)
    }
    private func removeChainObserver(_ aName: NSNotification.Name?) {
        NotificationCenter.default.removeObserver(self, name: aName, object: nil)
    }

    private func configureObserver() {
        addChainObserver(.chainManagerSyncStarted, #selector(chainManagerSyncStartedNotification(notification:)))
        addChainObserver(.chainManagerSyncFinished, #selector(chainManagerSyncFinishedNotification(notification:)))
        addChainObserver(.chainManagerSyncFailed, #selector(chainManagerSyncFailedNotification(notification:)))
        addChainObserver(.chainManagerSyncStateChanged, #selector(chainManagerSyncStateChangedNotification(notification:)))
    }
}

// MARK: Utils

extension SyncingActivityMonitor {
    private var chainSyncProgress: Double {
        model.combinedSyncProgress
    }

    private var shouldStopSyncing: Bool {
        let progress = chainSyncProgress

        if progress > Double.ulpOfOne && progress + Double.ulpOfOne < 1.0 {
            return false
        }
        else {
            return true
        }
    }

    private func shouldAcceptSyncNotification(_ notification: Notification) -> Bool {
        guard let chain = notification.userInfo?[kChainManagerNotificationChainKey] else {
            return false
        }

        let currentChain = DWEnvironment.sharedInstance().currentChain
        return currentChain.isEqual(chain)
    }
}

extension Notification.Name {
    // TODO: unused?
    static let syncStateChangedNotification: Notification.Name = .init(rawValue: "DWSyncStateChangedNotification")

    static let chainManagerSyncStarted: Notification.Name = .init(rawValue: "DSChainManagerSyncWillStartNotification")
    static let chainManagerSyncFinished: Notification.Name = .init(rawValue: "DSChainManagerSyncFinishedNotification")
    static let chainManagerSyncFailed: Notification.Name = .init(rawValue: "DSChainManagerSyncFailedNotification")
    static let peerManagerConnectedPeersDidChange: Notification.Name = .init(rawValue: "DSPeerManagerConnectedPeersDidChangeNotification")
    static let chainManagerSyncStateChanged: Notification.Name = .init(rawValue: "DSChainManagerSyncStateDidChangeNotification")
}
