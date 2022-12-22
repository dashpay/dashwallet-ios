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

// MARK: - CrowdNodeModelObjcWrapper

@objc public class CrowdNodeModelObjcWrapper: NSObject {
    @objc public class func getRootVC() -> UIViewController {
        let state = CrowdNode.shared.signUpState

        switch state {
        case .finished:
            return CrowdNodePortalController.controller()

        case .fundingWallet, .acceptingTerms, .signingUp:
            return AccountCreatingController.controller()

        case .acceptTermsRequired:
            return NewAccountViewController.controller()

        default:
            if DWGlobalOptions.sharedInstance().crowdNodeInfoShown {
                return GettingStartedViewController.controller()
            }
            else {
                return WelcomeToCrowdNodeViewController.controller()
            }
        }
    }
}

enum CrowdNodePortalItem: CaseIterable {
    case deposit
    case withdraw
    case onlineAccount
    case support
}

extension CrowdNodePortalItem {
    var title: String {
        switch self {
        case .deposit:
            return NSLocalizedString("Deposit", comment: "CrowdNode Portal")
        case .withdraw:
            return NSLocalizedString("Withdraw", comment: "CrowdNode Portal")
        case .onlineAccount:
            return NSLocalizedString("Create Online Account", comment: "CrowdNode Portal")
        case .support:
            return NSLocalizedString("CrowdNode Support", comment: "CrowdNode Portal")
        }
    }

    var subtitle: String {
        switch self {
        case .deposit:
            return NSLocalizedString("DashWallet ➝ CrowdNode", comment: "CrowdNode Portal")
        case .withdraw:
            return NSLocalizedString("CrowdNode ➝ DashWallet", comment: "CrowdNode Portal")
        case .onlineAccount:
            return NSLocalizedString("Protect your savings", comment: "CrowdNode Portal")
        case .support:
            return ""
        }
    }

    var icon: String {
        switch self {
        case .deposit:
            return "image.crowdnode.deposit"
        case .withdraw:
            return "image.crowdnode.withdraw"
        case .onlineAccount:
            return "image.crowdnode.online"
        case .support:
            return "image.crowdnode.support"
        }
    }
    
    var iconCircleColor: UIColor {
        switch self {
        case .deposit:
            return UIColor.systemGreen
            
        default:
            return UIColor.dw_dashBlue()
        }
    }
    
    func isDisabled(_ crowdNodeBalance: UInt64, _ walletBalance: UInt64) -> Bool {
        switch self {
        case .deposit:
            return walletBalance <= 0
            
        case .withdraw:
            return crowdNodeBalance <= 0
            
        default:
            return false
        }
    }
    
    
    func info(_ crowdNodeBalance: UInt64) -> String {
        switch self {
        case .deposit:
            let negligibleAmount = CrowdNode.minimumDeposit / 50
            let minimumDeposit = DSPriceManager.sharedInstance().string(forDashAmount: Int64(CrowdNode.minimumDeposit)) ?? String(CrowdNode.minimumDeposit)
            
            if (crowdNodeBalance < negligibleAmount) {
                return NSLocalizedString("Deposit at least \(minimumDeposit) to start earning", comment: "CrowdNode Portal")
            } else {
                return NSLocalizedString("Deposit \(minimumDeposit) to start earning", comment: "CrowdNode Portal")
            }
        case .withdraw:
            return NSLocalizedString("Verification Required", comment: "CrowdNode Portal")
        default:
            return ""
        }
    }
}

// MARK: - CrowdNodeModel

@MainActor
final class CrowdNodeModel {
    private var cancellableBag = Set<AnyCancellable>()
    private let crowdNode = CrowdNode.shared
    private var signUpTaskId: UIBackgroundTaskIdentifier = .invalid

    public static let shared: CrowdNodeModel = .init()

    @Published private(set) var outputMessage = ""
    @Published private(set) var accountAddress = ""
    @Published private(set) var signUpEnabled = false
    @Published private(set) var signUpState: CrowdNode.SignUpState
    @Published private(set) var crowdNodeBalance: UInt64 = 0
    @Published private(set) var walletBalance: UInt64 = 0
    @Published private(set) var hasEnoughWalletBalance = false
    @Published private(set) var animateBalanceLabel = false

    var isInterrupted: Bool {
        crowdNode.signUpState == .acceptTermsRequired
    }

    var showNotificationOnResult: Bool {
        get { crowdNode.showNotificationOnResult }
        set(value) { crowdNode.showNotificationOnResult = value }
    }

    var needsBackup: Bool { DWGlobalOptions.sharedInstance().walletNeedsBackup }
    var canSignUp: Bool { !needsBackup && hasEnoughWalletBalance }
    
    let portalItems: [CrowdNodePortalItem] = CrowdNodePortalItem.allCases

    init() {
        signUpState = crowdNode.signUpState
        observeState()
        observeBalances()
    }

    func getAccountAddress() {
        if crowdNode.accountAddress.isEmpty {
            accountAddress = DWEnvironment.sharedInstance().currentAccount.receiveAddress ?? ""
        }
        else {
            accountAddress = crowdNode.accountAddress
        }
    }

    func signUp() {
        Task {
            let promptMessage: String

            if isInterrupted {
                promptMessage = NSLocalizedString("Accept Terms Of Use", comment: "")
            }
            else {
                promptMessage = NSLocalizedString("Sign up to CrowdNode", comment: "")
            }

            if !accountAddress.isEmpty {
                self.accountAddress = accountAddress

                if await authenticate(message: promptMessage) {
                    signUpEnabled = false
                    await persistentSignUp(accountAddress: accountAddress)
                }
            }
        }
    }

    func authenticate(message: String? = nil, allowBiometric: Bool = true) async -> Bool {
        let biometricEnabled = DWGlobalOptions.sharedInstance().biometricAuthEnabled
        return await DSAuthenticationManager.sharedInstance().authenticate(withPrompt: message,
                                                                           usingBiometricAuthentication: allowBiometric &&
                                                                               biometricEnabled,
                                                                           alertIfLockout: true).0
    }

    func didShowInfoScreen() {
        DWGlobalOptions.sharedInstance().crowdNodeInfoShown = true
    }

    private func persistentSignUp(accountAddress: String) async {
        signUpTaskId = UIApplication.shared.beginBackgroundTask(withName: "finish_signup") {
            if self.signUpTaskId != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(self.signUpTaskId)
                self.signUpTaskId = UIBackgroundTaskIdentifier.invalid
            }
        }

        await crowdNode.signUp(accountAddress: accountAddress)

        if signUpTaskId != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(signUpTaskId)
            signUpTaskId = UIBackgroundTaskIdentifier.invalid
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
}

extension CrowdNodeModel {
    func refreshBalance() {
        crowdNode.refreshBalance(retries: 1)
    }
    
    private func observeBalances() {
        checkBalance()
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in self?.checkBalance() }
            .store(in: &cancellableBag)
        
        crowdNode.$balance
            .assign(to: \.crowdNodeBalance, on: self)
            .store(in: &cancellableBag)
        
        crowdNode.$isBalanceLoading
            .assign(to: \.animateBalanceLabel, on: self)
            .store(in: &cancellableBag)
    }

    private func checkBalance() {
        walletBalance = DWEnvironment.sharedInstance().currentAccount.balance
        hasEnoughWalletBalance = walletBalance >= CrowdNode.minimumRequiredDash
    }
}

extension CrowdNodeModel {
    func deposit(amount: Int64) async throws {
        guard amount > 0 else { return }
        try await crowdNode.deposit(amount: UInt64(amount))
    }

    func withdraw(permil: UInt) async throws {
        guard permil > 0 else { return }
        try await crowdNode.withdraw(permil: permil)
    }
}
