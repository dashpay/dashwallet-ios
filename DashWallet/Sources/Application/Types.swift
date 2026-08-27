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

// MARK: - NetworkStatus

public enum NetworkStatus {
    case online
    case offline
    /// No path has been reported yet, so reachability is genuinely not known.
    ///
    /// `NWPathMonitor` answers asynchronously on a background queue, and
    /// `startMonitoring()` deliberately does not block the main thread waiting
    /// for it. Reporting `.offline` in that window would be a guess — and one
    /// that flashes "no network" at users who are perfectly online.
    ///
    /// Treat it as "do not decide yet": show offline UI on `.offline` only, and
    /// keep gating actions on `== .online` so nothing acts on an unknown path.
    case unknown
}

extension NetworkReachability {
    var networkStatus: NetworkStatus {
        guard hasDeterminedReachability else { return .unknown }
        return isReachable ? .online : .offline
    }
}
