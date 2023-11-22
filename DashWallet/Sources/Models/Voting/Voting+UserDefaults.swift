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

private let kIsVotingInfoShown = "votingInfoShownKey"
private let kIsRequestInfoShown = "requestUsernameInfoShownKey"

// MARK: - VotingPrefs

class VotingPrefs {
    public static let shared: VotingPrefs = .init()
    
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
}
