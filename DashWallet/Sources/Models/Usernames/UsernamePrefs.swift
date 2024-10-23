//  
//  Created by Andrei Ashikhmin
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

import Foundation

private let kCoinJoinMixDashShown = "coinJoinMixDashShownKey"
private let kJoinDashPayInfoShown = "joinDashPayInfoShownKey"

// MARK: - UsernamePrefs

class UsernamePrefs {
    public static let shared: UsernamePrefs = .init()
    
    private var _mixDashShown: Bool? = nil
    var mixDashShown: Bool {
        get { _mixDashShown ?? UserDefaults.standard.bool(forKey: kCoinJoinMixDashShown) }
        set(value) {
            _mixDashShown = value
            UserDefaults.standard.set(value, forKey: kCoinJoinMixDashShown)
        }
    }
    
    private var _joinDashPayInfoShown: Bool? = nil
    var joinDashPayInfoShown: Bool {
        get { _joinDashPayInfoShown ?? UserDefaults.standard.bool(forKey: kJoinDashPayInfoShown) }
        set(value) {
            _joinDashPayInfoShown = value
            UserDefaults.standard.set(value, forKey: kJoinDashPayInfoShown)
        }
    }
}
