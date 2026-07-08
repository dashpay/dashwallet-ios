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
import SwiftDashSDK
import WebKit

// MARK: - CrowdNodeModelObjcWrapper

@objc
public class CrowdNodeModelObjcWrapper: NSObject {
    @objc
    public class func getRootVC() -> UIViewController {
        CrowdNode.shared.restoreState()
        let state = CrowdNode.shared.signUpState

        switch state {
        case .finished, .linkedOnline:
            return CrowdNodePortalController.controller()

        case .fundingWallet, .acceptingTerms, .signingUp:
            return AccountCreatingController.controller()

        case .acceptTermsRequired:
            return NewAccountViewController.controller(online: false)

        default:
            if CrowdNodeDefaults.shared.infoShown {
                return GettingStartedViewController.controller()
            }
            else {
                return WelcomeToCrowdNodeViewController.controller()
            }
        }
    }
}

// MARK: - CrowdNodeModel

@MainActor
final class CrowdNodeModel {
    private var cancellableBag = Set<AnyCancellable>()
    private let crowdNode = CrowdNode.shared
    private var signUpTaskId: UIBackgroundTaskIdentifier = .invalid
    private(set) var emailForAccount = ""
    private let prefs = CrowdNodeDefaults.shared

    public static let shared: CrowdNodeModel = .init()

    @Published private(set) var outputMessage = ""
    @Published private(set) var accountAddress = ""
    @Published private(set) var signUpEnabled = false
    @Published private(set) var signUpState: CrowdNode.SignUpState
    @Published private(set) var onlineAccountState: CrowdNode.OnlineAccountState
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
        get { !prefs.withdrawalLimitsInfoShown }
        set(value) { prefs.withdrawalLimitsInfoShown = !value }
    }

    var shouldShowConfirmationDialog: Bool {
        get { onlineAccountState == .confirming && !prefs.confirmationDialogShown }
        set(value) { prefs.confirmationDialogShown = !value }
    }

    var shouldShowOnlineInfo: Bool {
        get { signUpState != .linkedOnline && !prefs.onlineInfoShown }
        set(value) { prefs.onlineInfoShown = !value }
    }

    var needsBackup: Bool { DWGlobalOptions.sharedInstance().walletNeedsBackup }
    var canSignUp: Bool { !needsBackup && hasEnoughWalletBalance }
    var shouldShowFirstDepositBanner: Bool {
        return !crowdNode.hasAnyDeposits() && crowdNodeBalance < CrowdNode.minimumDeposit
    }

    var canWithdraw: Bool {
        let allAvailableFunds = SwiftDashSDKWalletState.shared.balance?.spendable ?? 0
        return allAvailableFunds >= CrowdNode.minimumLeftoverBalance
    }

    var buyDashButtonText: String {
        if DWEnvironment.sharedInstance().currentChain.isMainnet() {
            return NSLocalizedString("Buy Dash", comment: "CrowdNode")
        } else {
            return ""
        }
    }

    var primaryAddress: String? { crowdNode.primaryAddress }

    let portalItems: [CrowdNodePortalItem] = CrowdNodePortalItem.allCases
    var withdrawalLimits: [Int] { [
        Int(prefs.crowdNodeWithdrawalLimitPerTx / kOneDash),
        Int(prefs.crowdNodeWithdrawalLimitPerHour / kOneDash),
        Int(prefs.crowdNodeWithdrawalLimitPerDay / kOneDash),
    ] }

    init() {
        signUpState = crowdNode.signUpState
        onlineAccountState = crowdNode.onlineAccountState
        observeState()
        observeBalances()

        crowdNode.restoreState()
        getAccountAddress()
    }

    func getAccountAddress() {
        if crowdNode.accountAddress.isEmpty {
            accountAddress = SwiftDashSDKReceiveAddressReader.receiveAddress() ?? ""
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
                if await authenticate(message: promptMessage) {
                    signUpEnabled = false
                    await persistentSignUp(accountAddress: accountAddress)
                }
            }
        }
    }

    func authenticate(message: String? = nil, allowBiometric: Bool = true) async -> Bool {
        let biometricEnabled = DWGlobalOptions.sharedInstance().biometricAuthEnabled
        let outcome = await AuthenticationService.shared.authenticate(
            usingBiometrics: allowBiometric && biometricEnabled, spendAmount: nil)
        if case .authenticated = outcome { return true }
        return false
    }

    func didShowInfoScreen() {
        prefs.infoShown = true
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

    func clearError() {
        crowdNode.apiError = nil
    }

    private func observeState() {
        crowdNode.$signUpState
            .sink { [weak self] state in
                guard let wSelf = self else { return }
                var signUpEnabled = false
                var outputMessage = ""

                switch state {
                case .notInitiated, .notStarted:
                    signUpEnabled = true
                    WKWebView.cleanCrowdNodeCache()
                    wSelf.emailForAccount = ""
                    wSelf.getAccountAddress()

                case .acceptTermsRequired, .error:
                    signUpEnabled = true

                case .fundingWallet, .signingUp:
                    outputMessage = NSLocalizedString("Your CrowdNode account is creating…", comment: "CrowdNode")

                case .acceptingTerms:
                    outputMessage = NSLocalizedString("Accepting terms of use…", comment: "CrowdNode")

                case .linkedOnline:
                    wSelf.accountAddress = wSelf.crowdNode.accountAddress

                default:
                    break
                }

                wSelf.signUpState = state
                wSelf.signUpEnabled = signUpEnabled
                wSelf.outputMessage = outputMessage
            }
            .store(in: &cancellableBag)

        crowdNode.$apiError
            .sink { [weak self] error in self?.error = error }
            .store(in: &cancellableBag)

        crowdNode.$onlineAccountState
            .sink { [weak self] state in self?.onlineAccountState = state }
            .store(in: &cancellableBag)
    }
}

extension CrowdNodeModel {
    func refreshBalance() {
        crowdNode.refreshBalance(retries: 1)
    }

    private func observeBalances() {
        checkBalance()
        SwiftDashSDKWalletState.shared.$balance
            .receive(on: RunLoop.main)
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
        walletBalance = SwiftDashSDKWalletState.shared.balance?.total ?? 0
        hasEnoughWalletBalance = walletBalance >= CrowdNode.minimumRequiredDash
    }
}

// MARK: deposit / withdraw

extension CrowdNodeModel {
    func deposit(amount: UInt64) async throws -> Bool {
        guard amount > 0 else { return false }

        let usingBiometric = AuthenticationService.shared.canUseBiometricAuthentication(forAmount: amount)
        if await authenticate(allowBiometric: usingBiometric) {
            try await crowdNode.deposit(amount: amount)
            return true
        }

        return false
    }

    func withdraw(amount: UInt64) async throws -> Bool {
        guard amount > 0 && walletBalance >= CrowdNode.minimumLeftoverBalance else { return false }

        guard await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled) == .ok else { return false }

        // Signed message == the exact string requestWithdrawal sends as the
        // `amount` API parameter (its `.value` — `String(describing:)`).
        guard let signature = CrowdNodeMessageSigner.sign(
            message: String(amount), forAddress: crowdNode.accountAddress) else { return false }

        try await crowdNode.withdraw(amount: amount, signature: signature.base64EncodedString())
        return true
    }

    /// Fee for an average-size tx at the app's 1 duff/byte rate — the same
    /// figure DashSync's `feeForTxSize:` produced (`size × TX_FEE_PER_B`, the
    /// FEE_PER_KB_URL branch is compiled out) and the rate
    /// `SwiftDashSDKTransactionSender` builds with (1000 sat/kB).
    private static func estimatedFee(forTxSize size: UInt64) -> UInt64 {
        size
    }

    func adjustedWithdrawalAmount(requestedAmount: UInt64) -> UInt64 {
        let requestPermil = crowdNode.calculateWithdrawalPermil(forAmount: requestedAmount)
        let requestValue = CrowdNode.apiOffset + UInt64(requestPermil)

        let inQueueResponse = CrowdNode.apiOffset + ApiCode.withdrawalQueue.rawValue
        let inQueueResponseFee = Self.estimatedFee(forTxSize: 372) // Average size of the response tx.
        let withdrawalTxFee = Self.estimatedFee(forTxSize: 225) // Average size of the withdrawal tx.

        // CrowdNode gets the withdrawal request, adds it to the balance,
        // sends the InQueue response and then calculates withdrawal amount from what's left.
        let adjustedResult = (crowdNodeBalance + requestValue - inQueueResponse - inQueueResponseFee) * requestPermil / ApiCode.withdrawAll.rawValue - withdrawalTxFee

        return min(crowdNodeBalance, adjustedResult)
    }
}

// MARK: online account
extension CrowdNodeModel {
    func linkOnlineAccount() -> URL {
        precondition(!accountAddress.isEmpty)
        crowdNode.trackLinkingAccount(address: accountAddress)

        return URL(string: CrowdNode.apiLinkUrl + accountAddress)!
    }

    func cancelLinkingOnlineAccount() {
        crowdNode.stopTrackingLinked()
        WKWebView.cleanCrowdNodeCache()
    }

    func signAndSendEmail(email: String) async throws -> Bool {
        guard !crowdNode.accountAddress.isEmpty else { return false }
        emailForAccount = email

        guard await AuthenticationGate.authenticate(
            biometric: DWGlobalOptions.sharedInstance().biometricAuthEnabled) == .ok else { return false }

        guard let signature = CrowdNodeMessageSigner.sign(
            message: email, forAddress: crowdNode.accountAddress) else { return false }

        try await crowdNode.registerEmailForAccount(email: email, signature: signature.base64EncodedString())
        return true
    }

    func finishSignUpToOnlineAccount() {
        crowdNode.setOnlineAccountCreated()
    }
}

// MARK: - CrowdNodeMessageSigner

/// Dash "signed message" production for the CrowdNode API
/// (withdrawal / email registration), SwiftDashSDK-native — replaces the
/// frozen DashSync path (`wallet.privateKey(forAddress:fromSeed:)` +
/// `DSKeyManager.signMesasageDigest` + `magicDigest`), which reads a
/// wallet that has no keys for SDK-created wallets.
///
/// The CrowdNode account address is a BIP44 receive address of account 0;
/// the SDK exposes no address→derivation-index lookup, so the signer
/// re-derives public keys along `m/44'/<coin>'/0'/<chain>/<index>` and
/// matches the address's hash160. The scan is bounded — an address
/// outside it (never observed in practice; the address was issued by
/// this wallet) fails closed with nil, never a wrong-key signature.
@MainActor
enum CrowdNodeMessageSigner {
    private static let scanLimit: UInt32 = 300

    /// 65-byte compact recoverable signature over the DarkCoin-framed
    /// message (`DarkCoinMessage.framed`; the signer FFI SHA256d-hashes
    /// internally), or nil when the wallet/keys can't be resolved.
    static func sign(message: String, forAddress address: String) -> Data? {
        guard let network = SwiftDashSDKHost.shared.runningNetwork,
              let targetHash160 = hash160(ofAddress: address, network: network),
              let (_, wallet, _) = SwiftDashSDKHost.shared.derivationWallet(),
              let path = derivationPath(ofHash160: targetHash160, wallet: wallet, network: network),
              let wif = try? wallet.derivePrivateKey(path: path),
              let privateKey = WIFParser.parseWIF(wif) else {
            DWLogger.log("CrowdNode: message signing failed — no key resolved for account address")
            return nil
        }
        return try? RawKeySigner.sign(
            data: DarkCoinMessage.framed(message), privateKey: privateKey, network: network)
    }

    /// Base58Check-decoded P2PKH hash160 of `address` as lowercase hex
    /// (the format `computePublicKeyHashHex` emits).
    private static func hash160(ofAddress address: String, network: Network) -> String? {
        let paymentNetwork: PaymentNetwork = network == .mainnet ? .mainnet : .testnet
        guard let script = ScriptAddressCodec.scriptPubKey(forAddress: address, network: paymentNetwork),
              script.count == 25 else { return nil } // P2PKH only; P2SH can't be message-signed
        return script.subdata(in: 3 ..< 23).hexEncodedString()
    }

    /// Scan the BIP44 external chain (then internal, defensively) for the
    /// key whose hash160 matches. ~50 µs per derive; worst case ≈ 600
    /// derives once per withdraw/email action.
    private static func derivationPath(ofHash160 target: String, wallet: Wallet, network: Network) -> String? {
        let coin = network == .mainnet ? "5'" : "1'"
        for chain in [0, 1] {
            for index in 0 ..< scanLimit {
                let path = "m/44'/\(coin)/0'/\(chain)/\(index)"
                guard let pubHex = try? wallet.derivePublicKey(path: path),
                      let pubKey = Data(hex: pubHex) else { continue }
                if KeychainManager.computePublicKeyHashHex(pubKey) == target {
                    return path
                }
            }
        }
        return nil
    }
}
