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

private let kVotingEnabled = "votingEnabledKey"
private let kIsVotingInfoShown = "votingInfoShownKey"
private let kIsRequestInfoShown = "requestUsernameInfoShownKey"
private let kRequestedUsernameId = "requestedUsernameIdKey"
private let kRequestedUsername = "requestedUsernameKey"
private let kAlreadyPaid = "alreadyPaidForUsernameKey"
private let kVotingPanelClosed = "votingPanelWasClosedKey"

// MARK: - ObjcWrapper

@objc
class VotingPrefsWrapper: NSObject {
    @objc
    class func getIsEnabled() -> Bool {
        VotingPrefs.shared.votingEnabled
    }
    
    @objc
    class func setIsEnabled(value: Bool) {
        VotingPrefs.shared.votingEnabled = value
    }
}

// MARK: - VotingPrefs

class VotingPrefs {
    public static let shared: VotingPrefs = .init()
    
    init() {
        UserDefaults.standard.register(defaults: [kVotingEnabled : true])
    }
    
    private var _votingEnabled: Bool? = nil
    var votingEnabled: Bool {
        get { _votingEnabled ?? UserDefaults.standard.bool(forKey: kVotingEnabled) }
        set(value) {
            _votingEnabled = value
            UserDefaults.standard.set(value, forKey: kVotingEnabled)
        }
    }
    
    private var _votingInfoShown: Bool? = nil
    var votingInfoShown: Bool {
        get { _votingInfoShown ?? UserDefaults.standard.bool(forKey: kIsVotingInfoShown) }
        set(value) {
            _votingInfoShown = value
            UserDefaults.standard.set(value, forKey: kIsVotingInfoShown)
        }
    }
    
    private var _requestInfoShown: Bool? = nil
    var requestInfoShown: Bool {
        get { _requestInfoShown ?? UserDefaults.standard.bool(forKey: kIsRequestInfoShown) }
        set(value) {
            _requestInfoShown = value
            UserDefaults.standard.set(value, forKey: kIsRequestInfoShown)
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
    
    private var _requestedUsername: String? = nil
    var requestedUsername: String? {
        get { _requestedUsername ?? UserDefaults.standard.string(forKey: kRequestedUsername) }
        set(value) {
            _requestedUsername = value
            UserDefaults.standard.set(value, forKey: kRequestedUsername)
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
    
    private var _votingPanelClosed: Bool? = nil
    var votingPanelClosed: Bool {
        get { _votingPanelClosed ?? UserDefaults.standard.bool(forKey: kVotingPanelClosed) }
        set(value) {
            _votingPanelClosed = value
            UserDefaults.standard.set(value, forKey: kVotingPanelClosed)
        }
    }
}
