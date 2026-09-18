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
    
    init(initialState: JoinDashPayState) {
        self.initialState = initialState
        self.state = initialState
    }

    @MainActor
    func checkUsername() {
        let identity = DWCurrentUserIdentityInfo.shared.refreshedSnapshot()
        guard !identity.isLoading else {
            state = DWCurrentUserIdentityInfo.shared.isCurrentNetworkContextReady ? .loading : .callToAction
            username = ""
            return
        }

        if let pending = identity.pendingContestedName {
            // Same-seed recovery reconstructs this bookmark from Platform.
            // Surface the real voting state instead of offering Join DashPay
            // for an identity that already has a submitted name.
            self.state = .voting
            self.username = pending
        } else if identity.needsUsername {
            self.state = .usernameRequired
            self.username = ""
        } else if let registeredUsername = identity.username,
                  identity.hasIdentity,
                  UsernamePrefs.shared.joinDashPayDismissed {
            self.state = .registered
            self.username = registeredUsername
        } else {
            self.state = initialState
        }
    }

    @MainActor
    func finishLoadingAttempt() {
        if state == .loading { state = .retryLoading }
    }

    @MainActor
    func retryLoading() {
        DWCurrentUserIdentityInfo.shared.retryNameRefresh()
        checkUsername()
    }

    @MainActor
    func markAsDismissed() {
        UsernamePrefs.shared.joinDashPayDismissed = true
        self.checkUsername()
    }
}
