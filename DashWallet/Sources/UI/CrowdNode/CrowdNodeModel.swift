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


@objc public class CrowdNodeModelObjcWrapper: NSObject {
    @objc public class func getRootVC() -> UIViewController {
        return WelcomeToCrowdNodeViewController.controller()
//        let state = CrowdNode.shared.signUpState
//
//        switch state {
//        case .finished:
//            return CrowdNodePortalController.controller()
//
//        case .fundingWallet, .acceptingTerms, .signingUp:
//            return AccountCreatingController.controller()
//
//        default:
//            return NewAccountViewController.controller()
//        }
    }
}

@MainActor
final class CrowdNodeModel {
    private var cancellableBag = Set<AnyCancellable>()
    private let crowdNode = CrowdNode.shared
    private var signUpTaskId: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid

    public static let shared: CrowdNodeModel = .init()
    
    @Published var outputMessage: String = ""
    @Published var accountAddress: String = ""
    @Published var signUpEnabled: Bool = false
    @Published var signUpState: CrowdNode.SignUpState
    @Published var hasEnoughBalance: Bool = false
    
    var isInterrupted: Bool {
        crowdNode.signUpState == .acceptTermsRequired
    }
    var showNotificationOnResult: Bool {
        get { return crowdNode.showNotificationOnResult }
        set(value) { crowdNode.showNotificationOnResult = value }
    }

    init() {
        signUpState = crowdNode.signUpState
        observeState()
        observeBalance()
    }
    
    func getAccountAddress() {
        if isInterrupted {
            accountAddress = crowdNode.accountAddress
        } else {
            accountAddress = DWEnvironment.sharedInstance().currentAccount.receiveAddress ?? ""
        }
    }

    func signUp() {
        Task {
            let promptMessage: String
            
            if isInterrupted {
                promptMessage = NSLocalizedString("Accept Terms Of Use", comment: "")
            } else {
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
    
    private func observeState() {
        crowdNode.$signUpState
            .sink { [weak self] state in
                var signUpEnabled = false
                var outputMessage = ""

                switch state {
                case .notInitiated, .notStarted, .acceptTermsRequired, .error:
                    signUpEnabled = true

                case .fundingWallet, .signingUp:
                    outputMessage = NSLocalizedString("Your CrowdNode account is creating…", comment: "")
                    
                case .acceptingTerms:
                    outputMessage = NSLocalizedString("Accepting terms of use…", comment: "")

                default:
                    break
                }
                
                self?.signUpState = state
                self?.signUpEnabled = signUpEnabled
                self?.outputMessage = outputMessage
            }
            .store(in: &cancellableBag)
        
        crowdNode.restoreState()
        getAccountAddress()
    }
    
    private func observeBalance() {
        checkBalance()
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] balance in
                print("CrowdNode observe balance \(balance)")
                self?.checkBalance()
            }
            .store(in: &cancellableBag)
    }
    
    private func checkBalance() {
        print("CrowdNode checkBalance")
        self.hasEnoughBalance = DWEnvironment.sharedInstance().currentAccount.balance > CrowdNodeConstants.minimumRequiredDash
    }
}
