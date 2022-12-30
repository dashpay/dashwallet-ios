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

import UIKit

// MARK: - NetworkReachabilityHandling

protocol NetworkReachabilityHandling: AnyObject {
    var networkStatusDidChange: ((NetworkStatus) -> ())? { get set }
    var reachabilityObserver: Any! { get set }
}

extension NetworkReachabilityHandling {
    var networkStatus: NetworkStatus {
        reachability.networkStatus
    }

    internal var reachability: DSReachabilityManager { DSReachabilityManager.shared() }

    public func startNetworkMonitoring() {
        if !reachability.isMonitoring {
            reachability.startMonitoring()
        }

        reachabilityObserver = NotificationCenter.default
            .addObserver(forName: NSNotification.Name(rawValue: "org.dash.networking.reachability.change"),
                         object: nil,
                         queue: nil,
                         using: { [weak self] _ in
                             self?.updateNetworkStatus()
                         })

        updateNetworkStatus()
    }

    public func stopNetworkMonitoring() {
        NotificationCenter.default.removeObserver(reachabilityObserver!)
    }

    private func updateNetworkStatus() {
        networkStatusDidChange?(networkStatus)
    }
}
