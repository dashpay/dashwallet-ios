//  
//  Created by Andrei Ashikhmin
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

import Combine

class CrowdNodeModel {
    private var cancellableBag = Set<AnyCancellable>()
    private let crowdNode = CrowdNode.shared
    
    @Published var outputMessage: String = ""
    @Published var accountAddress: String = ""
    @Published var isLoading: Bool = false
    @Published var signUpEnabled: Bool = false
    
    
    init() {
        self.accountAddress = crowdNode.accountAddress
        
        crowdNode.$signUpState
            .sink { [weak self] state in
                self?.signUpEnabled = false
                self?.isLoading = false
                
                switch state {
                case .notStarted:
                    self?.signUpEnabled = true
                    self?.outputMessage = NSLocalizedString("Sign up to CrowdNode", comment: "")
                    
                case .fundingWallet, .signingUp:
                    self?.isLoading = true
                    self?.outputMessage = NSLocalizedString("Your CrowdNode account is creating…", comment: "")
                    
                case .acceptingTerms:
                    self?.isLoading = true
                    self?.outputMessage = NSLocalizedString("Accepting terms of use…", comment: "")
                    
                case .finished:
                    self?.outputMessage = NSLocalizedString("Your CrowdNode account is set up and ready to use!", comment: "")
                    
                case .error:
                    self?.signUpEnabled = true
                    self?.outputMessage = NSLocalizedString("We couldn’t create your CrowdNode account.", comment: "") + " \(String(describing: self?.crowdNode.apiError?.localizedDescription))"
                    
                case .linkedOnline:
                    break
                }
            }
            .store(in: &cancellableBag)
    }
    
    @MainActor
    func signUp() {
        Task.init {
            if let accountAddress = DWEnvironment.sharedInstance().currentAccount.receiveAddress {
                print("CrowdNode account address: \(accountAddress)")
                self.accountAddress = accountAddress
                
                let success = await DSAuthenticationManager.sharedInstance().authenticate(
                    withPrompt: NSLocalizedString("Sign up to CrowdNode", comment: ""),
                    usingBiometricAuthentication: false, alertIfLockout: false
                ).0
            
                if (success) {
                    await crowdNode.signUp(accountAddress: accountAddress)
                }
            }
        }
    }
}
