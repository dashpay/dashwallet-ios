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

@MainActor
final class CrowdNodeModel {
    private var cancellableBag = Set<AnyCancellable>()
    private let crowdNode = CrowdNode.shared
    private var signUpTaskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid

    @Published var outputMessage: String = ""
    @Published var accountAddress: String = ""
    @Published var isLoading: Bool = false
    @Published var signUpEnabled: Bool = false
    var isInterrupted: Bool {
        crowdNode.signUpState == .acceptTermsRequired
    }

    init() {
        accountAddress = crowdNode.accountAddress

        crowdNode.$signUpState
            .sink { [weak self] state in
                self?.signUpEnabled = false
                self?.isLoading = false

                switch state {
                case .notInitiated, .notStarted:
                    self?.signUpEnabled = true
                    self?.outputMessage = NSLocalizedString("Sign up to CrowdNode", comment: "")

                case .fundingWallet, .signingUp:
                    self?.isLoading = true
                    self?.outputMessage = NSLocalizedString("Your CrowdNode account is creating…", comment: "")

                case .acceptTermsRequired:
                    self?.signUpEnabled = true
                    self?.outputMessage = NSLocalizedString("Accept terms of use", comment: "")
                    
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
        
        crowdNode.restoreState()
    }

    func signUp() {
        Task {
            let accountAddress: String
            let promptMessage: String
            
            if crowdNode.signUpState == .acceptTermsRequired {
                accountAddress = crowdNode.accountAddress
                promptMessage = NSLocalizedString("Accept Terms Of Use", comment: "")
            } else {
                accountAddress = DWEnvironment.sharedInstance().currentAccount.receiveAddress ?? ""
                promptMessage = NSLocalizedString("Sign up to CrowdNode", comment: "")
            }
            
            if !accountAddress.isEmpty {
                print("CrowdNode account address: \(accountAddress)")
                self.accountAddress = accountAddress
                
                let success = await DSAuthenticationManager.sharedInstance().authenticate(
                    withPrompt: promptMessage,
                    usingBiometricAuthentication: true, alertIfLockout: false
                ).0
                
                if success {
                    signUpEnabled = false
                    await persistentSignUp(accountAddress: accountAddress)
                }
            }
        }
    }
    
    private func persistentSignUp(accountAddress: String) async {
        self.signUpTaskId = UIApplication.shared.beginBackgroundTask (withName: "finish_signup") {
            if (self.signUpTaskId != UIBackgroundTaskIdentifier.invalid) {
                UIApplication.shared.endBackgroundTask(self.signUpTaskId)
                self.signUpTaskId = UIBackgroundTaskIdentifier.invalid
            }
        }

        await crowdNode.signUp(accountAddress: accountAddress)
    
        if (self.signUpTaskId != UIBackgroundTaskIdentifier.invalid) {
            UIApplication.shared.endBackgroundTask(self.signUpTaskId)
            self.signUpTaskId = UIBackgroundTaskIdentifier.invalid
        }
    }
}
