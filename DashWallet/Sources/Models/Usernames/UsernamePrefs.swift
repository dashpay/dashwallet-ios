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
private let kRequestedUsernameId = "requestedUsernameIdKey"
private let kAlreadyPaid = "alreadyPaidForUsernameKey"
private let kJoinDashPayDismissed = "joinDashPayDismissed"

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
    
    private var _requestedUsernameId: String? = nil
    var requestedUsernameId: String? {
        get { _requestedUsernameId ?? UserDefaults.standard.string(forKey: kRequestedUsernameId) }
        set(value) {
            _requestedUsernameId = value
            UserDefaults.standard.set(value, forKey: kRequestedUsernameId)
        }
    }
    
    private var _alreadyPaid: Bool? = nil
    var alreadyPaid: Bool {
        get { _alreadyPaid ?? UserDefaults.standard.bool(forKey: kAlreadyPaid) }
        set(value) {
            _alreadyPaid = value
            UserDefaults.standard.set(value, forKey: kAlreadyPaid)
        }
    }
    
    private var _joinDashPayDismissed: Bool? = nil
    var joinDashPayDismissed: Bool {
        get { _joinDashPayDismissed ?? UserDefaults.standard.bool(forKey: kJoinDashPayDismissed) }
        set(value) {
            _joinDashPayDismissed = value
            UserDefaults.standard.set(value, forKey: kJoinDashPayDismissed)
        }
    }
}
