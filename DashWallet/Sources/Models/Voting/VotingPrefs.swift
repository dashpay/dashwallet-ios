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
        get {
            let result = _votingEnabled ?? UserDefaults.standard.bool(forKey: kVotingEnabled)
            return result
        }
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
    
    private var _votingPanelClosed: Bool? = nil
    var votingPanelClosed: Bool {
        get { _votingPanelClosed ?? UserDefaults.standard.bool(forKey: kVotingPanelClosed) }
        set(value) {
            _votingPanelClosed = value
            UserDefaults.standard.set(value, forKey: kVotingPanelClosed)
        }
    }
}
