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

import Foundation
import Combine

@objc(DWCurrentUserProfileModelState)
enum CurrentUserProfileModelState: Int {
    case none
    case loading
    case done
    case error
}

@objc(DWCurrentUserProfileModel)
class CurrentUserProfileModel: NSObject, ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private var model = SyncModelImpl()
    @objc private(set) var state: CurrentUserProfileModelState = .none
    @objc let updateModel: DWDPUpdateProfileModel
    @Published private(set) var showJoinDashpay: Bool = true
    
    @objc var blockchainIdentity: DSBlockchainIdentity? {
        let platform = PlatformService.shared
        if platform.isRegistered, let username = platform.currentUsername {
            return DWEnvironment.sharedInstance().currentWallet.createBlockchainIdentity(forUsername: username)
        }

        if let username = DWGlobalOptions.sharedInstance().dashpayUsername {
            return DWEnvironment.sharedInstance().currentWallet.createBlockchainIdentity(forUsername: username)
        }

        return DWEnvironment.sharedInstance().currentWallet.defaultBlockchainIdentity
    }
    
    override init() {
        updateModel = DWDPUpdateProfileModel()
        super.init()
        
        model.$state
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.showJoinDashpay = self?.model.state == .syncDone
            }
            .store(in: &cancellableBag)
    }
    
    @objc func update() {
        guard blockchainIdentity != nil else {
            state = .none
            return
        }

        if state == .loading {
            return
        }

        state = .loading

        // Use PlatformService to fetch profile
        PlatformService.shared.fetchProfile { [weak self] user, error in
            guard let self = self else { return }
            if error != nil {
                self.state = .error
            } else {
                self.state = .done
            }
        }
    }
}
