//
//  Created by PT
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import UIKit

// MARK: - SyncModel

protocol SyncModel {
    var networkStatusDidChange: ((NetworkStatus) -> ())? { get set }
    var networkStatus: NetworkStatus { get }

    var stateDidChage: ((SyncingActivityMonitor.State) -> ())? { get set }
    var state: SyncingActivityMonitor.State { get }

    var progressDidChange: ((Double) -> ())? { get set }
    var progress: Double { get }
    
    func forceStartSyncingActivity()
}

// MARK: - SyncModelImpl

final class SyncModelImpl: SyncModel {
    var networkStatusDidChange: ((NetworkStatus) -> ())?

    var stateDidChage: ((SyncingActivityMonitor.State) -> ())?
    private(set) var state: SyncingActivityMonitor.State

    var progressDidChange: ((Double) -> ())?
    private(set) var progress: Double

    internal var reachabilityObserver: Any!
    private let syncMonitor: SyncingActivityMonitor

    init() {
        syncMonitor = SyncingActivityMonitor.shared
        state = syncMonitor.state
        progress = syncMonitor.progress
        syncMonitor.add(observer: self)

        startNetworkMonitoring()
    }

    func forceStartSyncingActivity() {
        syncMonitor.forceStartSyncingActivity()
    }

    deinit {
        syncMonitor.remove(observer: self)
        stopNetworkMonitoring()
    }
}

// MARK: NetworkReachabilityHandling

extension SyncModelImpl: NetworkReachabilityHandling { }

// MARK: SyncingActivityMonitorObserver


extension SyncModelImpl: SyncingActivityMonitorObserver {
    func syncingActivityMonitorProgressDidChange(_ progress: Double) {
        self.progress = progress
        progressDidChange?(progress)
    }

    func syncingActivityMonitorStateDidChange(previousState: SyncingActivityMonitor.State, state: SyncingActivityMonitor.State) {
        self.state = state
        stateDidChage?(state)
    }
}
