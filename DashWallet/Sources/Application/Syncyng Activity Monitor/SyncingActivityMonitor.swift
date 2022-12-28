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

    public var progress: Double = 0 {
        didSet {
            observers.forEach { $0.syncingActivityMonitorProgressDidChange(progress) }
        }
    }

    public var state: State = .unknown {
        didSet {
            guard state != oldValue else { return }

            if state == .syncDone {
                DWGlobalOptions.sharedInstance().isResyncingWallet = false
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

    @objc public func forceStartSyncingActivity() {
        startSyncingActivity()
    }

    @objc(addObserver:) public func add(observer: SyncingActivityMonitorObserver) {
        observers.append(observer)
    }

    @objc(removeObserver:) public func remove(observer: SyncingActivityMonitorObserver) {
        if let idx = observers.firstIndex(where: { $0 === observer }) {
            observers.remove(at: idx)
        }
    }

    // MARK: Notifications

    @objc func chainManagerSyncStartedNotification(notification: Notification) {
        guard shouldAcceptSyncNotification(notification) else { return }

        startSyncingActivity()
    }

    @objc func chainManagerParametersUpdatedNotification(notification: Notification) {
        guard shouldAcceptSyncNotification(notification) else { return }

        startSyncingActivity()
    }

    @objc func chainManagerSyncFinishedNotification(notification: Notification) {
        guard shouldAcceptSyncNotification(notification) else { return }
        guard shouldStopSyncing else { return }

        stopSyncingActivity(failed: false)
    }

    @objc func chainManagerSyncFailedNotification(notification: Notification) {
        guard shouldAcceptSyncNotification(notification) else { return }

        stopSyncingActivity(failed: true)
    }

    @objc func chainManagerChainBlocksDidChangeNotification(notification: Notification) {
        guard !isSyncing, chainSyncProgress < kSyncingCompleteProgress else { return }

        startSyncingActivity()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.removeObserver(reachabilityObserver!)
    }

    @objc public static let shared = SyncingActivityMonitor()
}

// MARK: Suncing

extension SyncingActivityMonitor {
    private func startSyncingIfNeeded() {
        guard DWEnvironment.sharedInstance().currentChainManager.peerManager.connected else {
            return
        }

        startSyncingActivity()
    }

    private func startSyncingActivity() {
        guard !isSyncing else { return }

        progress = 0
        lastPeakDate = nil

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(syncLoop), object: nil)
        syncLoop()
    }

    private func stopSyncingActivity(failed: Bool) {
        guard isSyncing else { return }

        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(syncLoop), object: nil)

        state = failed ? .syncFailed : .syncDone
    }

    @objc private func syncLoop() {
        guard reachability.networkReachabilityStatus != .notReachable else {
            state = .noConnection
            return
        }

        let progress = chainSyncProgress

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
            self.progress = 1.0
            state = .syncDone
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

    private func configureObserver() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(chainManagerSyncStartedNotification(notification:)),
                                       name: .chainManagerSyncStarted, object: nil)
        notificationCenter.addObserver(self, selector: #selector(chainManagerParametersUpdatedNotification(notification:)),
                                       name: .chainManagerParametersUpdated, object: nil)
        notificationCenter.addObserver(self, selector: #selector(chainManagerSyncFinishedNotification(notification:)),
                                       name: .chainManagerSyncFinished, object: nil)
        notificationCenter.addObserver(self, selector: #selector(chainManagerSyncFailedNotification(notification:)),
                                       name: .chainManagerSyncFailed, object: nil)
        notificationCenter.addObserver(self, selector: #selector(chainManagerChainBlocksDidChangeNotification(notification:)),
                                       name: .chainManagerChainSyncBlocksDidChange, object: nil)
    }
}

// MARK: Utils

extension SyncingActivityMonitor {
    private var chainSyncProgress: Double {
        DWEnvironment.sharedInstance().currentChainManager.combinedSyncProgress
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
    static let syncStateChangedNotification: Notification.Name = .init(rawValue: "DWSyncStateChangedNotification")

    static let chainManagerSyncStarted: Notification.Name = .init(rawValue: "DSChainManagerSyncWillStartNotification")
    static let chainManagerParametersUpdated: Notification
        .Name = .init(rawValue: "DSChainManagerSyncParametersUpdatedNotification")
    static let chainManagerSyncFinished: Notification.Name = .init(rawValue: "DSChainManagerSyncFinishedNotification")
    static let chainManagerSyncFailed: Notification.Name = .init(rawValue: "DSChainManagerSyncFailedNotification")
    static let chainManagerChainSyncBlocksDidChange: Notification
        .Name = .init(rawValue: "DSChainChainSyncBlocksDidChangeNotification")
}
