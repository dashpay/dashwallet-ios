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

@objc
public class CrowdNodeModelObjcWrapper: NSObject {
    @objc public class func getRootVC() -> UIViewController {
        CrowdNode.shared.restoreState()
        let state = CrowdNode.shared.signUpState

        switch state {
        case .finished:
            return CrowdNodePortalController.controller()

        case .fundingWallet, .acceptingTerms, .signingUp:
            return AccountCreatingController.controller()

        case .acceptTermsRequired:
            return NewAccountViewController.controller(online: false)

        default:
            if CrowdNode.shared.infoShown {
                return GettingStartedViewController.controller()
            }
            else {
                return WelcomeToCrowdNodeViewController.controller()
            }
        }
    }
}

// MARK: - CrowdNodePortalItem

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
            return crowdNodeBalance <= 0 || walletBalance < CrowdNode.minimumLeftoverBalance

        default:
            return false
        }
    }


    func info(_ crowdNodeBalance: UInt64) -> String {
        switch self {
        case .deposit:
            let negligibleAmount = CrowdNode.minimumDeposit / 50
            let minimumDeposit = DSPriceManager.sharedInstance().string(forDashAmount: Int64(CrowdNode.minimumDeposit))!

            if crowdNodeBalance < negligibleAmount {
                return String.localizedStringWithFormat(NSLocalizedString("Deposit at least %@ to start earning", comment: "CrowdNode Portal"), minimumDeposit)
            } else {
                return String.localizedStringWithFormat(NSLocalizedString("Deposit %@ to start earning", comment: "CrowdNode Portal"), minimumDeposit)
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
    @Published var error: Error? = nil

    var isInterrupted: Bool {
        crowdNode.signUpState == .acceptTermsRequired
    }

    var showNotificationOnResult: Bool {
        get { crowdNode.showNotificationOnResult }
        set(value) { crowdNode.showNotificationOnResult = value }
    }
    
    var shouldShowWithdrawalLimitsDialog: Bool {
        get { !crowdNode.withdrawalLimitsInfoShown }
        set(value) { crowdNode.withdrawalLimitsInfoShown = !value }
    }

    var needsBackup: Bool { DWGlobalOptions.sharedInstance().walletNeedsBackup }
    var canSignUp: Bool { !needsBackup && hasEnoughWalletBalance }
    var shouldShowFirstDepositBanner: Bool {
        !crowdNode.hasAnyDeposits() && crowdNodeBalance < CrowdNode.minimumDeposit
    }

    let portalItems: [CrowdNodePortalItem] = CrowdNodePortalItem.allCases
    var withdrawalLimits: [Int] {[
        Int(crowdNode.crowdNodeWithdrawalLimitPerTx / kOneDash),
        Int(crowdNode.crowdNodeWithdrawalLimitPerHour / kOneDash),
        Int(crowdNode.crowdNodeWithdrawalLimitPerDay / kOneDash)
    ]}

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
                promptMessage = NSLocalizedString("Accept Terms Of Use", comment: "CrowdNode")
            }
            else {
                promptMessage = NSLocalizedString("Sign up to CrowdNode", comment: "CrowdNode")
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
        crowdNode.infoShown = true
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
                    outputMessage = NSLocalizedString("Your CrowdNode account is creating…", comment: "CrowdNode")

                case .acceptingTerms:
                    outputMessage = NSLocalizedString("Accepting terms of use…", comment: "CrowdNode")

                default:
                    break
                }

                self?.signUpState = state
                self?.signUpEnabled = signUpEnabled
                self?.outputMessage = outputMessage
            }
            .store(in: &cancellableBag)

        crowdNode.$apiError
            .sink { [weak self] error in self?.error = error }
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
    func deposit(amount: Int64) async throws -> Bool {
        guard amount > 0 else { return false }

        let usingBiometric = DSAuthenticationManager.sharedInstance().canUseBiometricAuthentication(forAmount: UInt64(amount))
        if await authenticate(allowBiometric: usingBiometric) {
            try await crowdNode.deposit(amount: UInt64(amount))
            return true
        }

        return false
    }

    func withdraw(amount: Int64) async throws -> Bool {
        guard amount > 0 && walletBalance >= CrowdNode.minimumLeftoverBalance else { return false }
        
        if !DSAuthenticationManager.sharedInstance().didAuthenticate {
            let usingBiometric = DSAuthenticationManager.sharedInstance().canUseBiometricAuthentication(forAmount: UInt64(amount))
            let authenticated = await authenticate(allowBiometric: usingBiometric)
            
            if !authenticated {
                return false
            }
        }
        
        try await crowdNode.withdraw(amount: UInt64(amount))
        return true
    }
}

// MARK: online account
extension CrowdNodeModel {
    func linkOnlineAccount() -> URL {
        precondition(!accountAddress.isEmpty)
        crowdNode.trackLinkingAccount(address :accountAddress)
        
        return URL(string: CrowdNode.apiLinkUrl + crowdNode.accountAddress)!
    }
}
