//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

class JoinDashPayViewModel: ObservableObject {
    private let initialState: JoinDashPayState
    @Published private(set) var state: JoinDashPayState
    @Published private(set) var username: String = ""
    
    private var identity: DSIdentity? {
        if MOCK_DASHPAY.boolValue {
            if let username = DWGlobalOptions.sharedInstance().dashpayUsername {
                return DWEnvironment.sharedInstance().currentWallet.createIdentity(forUsername: username)
            }
        }
        return DWEnvironment.sharedInstance().currentWallet.defaultIdentity
    }
    
    init(initialState: JoinDashPayState) {
        self.initialState = initialState
        self.state = initialState
    }

    @MainActor
    func checkUsername() {
        if identity != nil && DWGlobalOptions.sharedInstance().dashpayRegistrationCompleted && UsernamePrefs.shared.joinDashPayDismissed { // TODO: MOCK_DASHPAY simplify
            self.state = .registered
            self.username = identity?.currentDashpayUsername ?? ""
        } else {
            Task {
                // TODO: MOCK_DASHPAY replace with actual state check
                if let requestId = UsernamePrefs.shared.requestedUsernameId {
                    let dao = UsernameRequestsDAOImpl.shared
                    guard let request = await dao.get(byRequestId: requestId) else { return }
                    self.username = request.username
                    
                    if request.isApproved {
                        self.state = .approved
                        
                        if DWGlobalOptions.sharedInstance().dashpayRegistrationCompleted != true {
                            DWGlobalOptions.sharedInstance().dashpayRegistrationCompleted = true
                            NotificationCenter.default.post(name: NSNotification.Name.DWDashPayRegistrationStatusUpdated, object: nil)
                        }
                    } else if request.blockVotes > 0 {
                        self.state = .blocked
                    } else {
                        self.state = .voting
                    }
                } else {
                    self.state = initialState
                }
            }
        }
    }
    
    @MainActor
    func markAsDismissed() {
        UsernamePrefs.shared.joinDashPayDismissed = true
        
        if state != .approved {
            UsernamePrefs.shared.requestedUsernameId = nil
        }
        
        self.checkUsername()
    }
}
