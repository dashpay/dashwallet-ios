//  
//  Created by Pavel Tikhonenko
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

extension PortalModel.Service {
    var title: String {
        switch self {
        case .coinbase: return NSLocalizedString("Coinbase", comment: "Dash Portal")
        case .uphold: return NSLocalizedString("Uphold", comment: "Dash Portal")
        }
    }
    
    var icon: String {
        switch self {
        case .coinbase: return "portal.coinbase"
        case .uphold: return "portal.uphold"
        }
    }
    
    var status: Bool {
        switch self {
        case .coinbase: return false
        case .uphold: return true
        }
    }
}

class PortalModel {
    var networkStatusDidChange: ((NetworkStatus) -> ())?
    
    enum Service: CaseIterable {
        case coinbase
        case uphold
    }
    
    enum NetworkStatus {
        case online
        case offline
    }
    
    var services: [Service] = Service.allCases
    var networkStatus: NetworkStatus!
    
    private var reachability: DSReachabilityManager { return DSReachabilityManager.shared() }
    private var reachabilityObserver: Any!
     
    init() {
        initializeReachibility()
    }
    
    private func initializeReachibility() {
        if (!reachability.isMonitoring) {
            reachability.startMonitoring()
        }
        
        self.reachabilityObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "org.dash.networking.reachability.change"),
                                                                           object: nil,
                                                                           queue: nil,
                                                                           using: { [weak self] notification in
            self?.updateNetworkStatus()
        })
        
        updateNetworkStatus()
    }
    
    private func updateNetworkStatus() {
        networkStatus = reachability.networkStatus
        networkStatusDidChange?(networkStatus)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(reachabilityObserver!)
    }
}

extension DSReachabilityManager {
    var networkStatus:  PortalModel.NetworkStatus {
        return self.isReachable ? .online : .offline
    }
}
