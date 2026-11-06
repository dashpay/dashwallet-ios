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
        if WalletEnvironment.isMainnet {
            return NSLocalizedString("Buy Dash", comment: "CrowdNode")
        } else {
            return ""
        }
    }

    var primaryAddress: String? { crowdNode.primaryAddress }

    var portalItems: [CrowdNodePortalItem] {
        return CrowdNodePortalItem.allCases.filter { item in
            switch item {
            case .deposit, .onlineAccount:
                return false
            default:
                return true
            }
        }
    }
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
/// The CrowdNode account address is a BIP44 receive address of account 0.
/// The SDK wallet finds it in Rust with a bounded scan: BIP44 account 0,
/// external chain then internal, indexes 0 to 299. `sign` takes the key at
/// that path, which Rust derives without handing the phrase to Swift, and the
/// ownership check takes the path alone, which needs no phrase. The two
/// callers treat a miss differently. `sign` fails closed with nil, never a
/// wrong-key signature. The ownership check answers "not found within the
/// bound", because the search can miss an address the wallet owns (ticket
/// 32026). Whether it misses through the index bound or through the set of
/// derivation paths it walks is not established, so a miss is not evidence
/// the address is foreign.
@MainActor
enum CrowdNodeMessageSigner {
    /// 65-byte compact recoverable signature over the DarkCoin-framed
    /// message (`DarkCoinMessage.framed`; the signer FFI SHA256d-hashes
    /// internally), or nil when the wallet/keys can't be resolved.
    static func sign(message: String, forAddress address: String) -> Data? {
        guard let network = SwiftDashSDKHost.shared.runningNetwork,
              let key = try? SwiftDashSDKHost.shared.wallet?.bip44AddressPrivateKey(address: address),
              let privateKey = Data(hex: key.hex) else {
            DWLogger.log("CrowdNode: message signing failed — no key resolved for account address")
            return nil
        }
        return try? RawKeySigner.sign(
            data: DarkCoinMessage.framed(message), privateKey: privateKey, network: network)
    }

    /// What the ownership check needs from the running wallet: whether an
    /// address is a P2PKH address of the running network, and the wallet's
    /// lookup of an address's derivation path, which throws when the wallet
    /// can't answer. `liveOwnership()` returns nil when the SDK wallet or the
    /// network isn't up yet.
    struct OwnershipLookup {
        let isP2PKH: (String) -> Bool
        let derivationPath: (String) throws -> String?
    }

    /// Why the ownership check answered what it did.
    ///
    /// `ownsAddress`'s `Bool?` collapsed two very different unknowns into
    /// `nil`: the wallet not being up yet, and the bounded search running out.
    /// They deserve different handling — a search that ran out is a durable
    /// verdict for this wallet, while a wallet that is not up means the check
    /// never ran, and a restore must not memoize a pass built on it as
    /// fruitless.
    enum Ownership: Equatable {
        /// The wallet found the address's path: this address is the active
        /// wallet's.
        case owned
        /// The address cannot be this wallet's — not a P2PKH address of the
        /// running network. The only answer that justifies destroying prefs.
        case foreign
        /// The SDK wallet or the network is not up, or the wallet could not
        /// answer, so nothing was checked.
        case walletUnavailable
        /// The wallet's search ran to its bound without finding the address.
        /// Not evidence the address is foreign (ticket 32026) — the bound
        /// exists for cost.
        case notFoundWithinBound

        /// Whether this verdict came from a check that actually ran.
        var wasChecked: Bool { self != .walletUnavailable }
    }

    /// Four-case ownership check. Prefer this over `ownsAddress`, which
    /// flattens `walletUnavailable` and `notFoundWithinBound` into `nil`.
    static func ownership(of address: String) -> Ownership {
        ownership(of: address, using: liveOwnership())
    }

    /// The verdict rule on its own, with the wallet reduced to two closures so
    /// it can be pinned without an SDK host: a nil `lookup` is "the wallet
    /// isn't up", and a throwing lookup is "the wallet could not answer". The
    /// path is asked for only for a P2PKH address of the running network.
    static func ownership(of address: String, using lookup: OwnershipLookup?) -> Ownership {
        guard let lookup else { return .walletUnavailable }
        guard lookup.isP2PKH(address) else {
            return .foreign // not a P2PKH address of this network ⇒ not ours
        }
        do {
            return try lookup.derivationPath(address) != nil ? .owned : .notFoundWithinBound
        } catch {
            return .walletUnavailable
        }
    }

    /// Tri-state wallet-ownership check for a persisted CrowdNode account
    /// address (a BIP44 acct-0 receive address, so the wallet's bounded
    /// search finds it): `true` when the wallet finds its path; `false`
    /// only when the address cannot be this wallet's (not a P2PKH address of
    /// the running network); `nil` when ownership is unknown — the
    /// wallet/network isn't up yet (a relaunch validates prefs before the SDK
    /// starts), or the search ran out before reaching the address's index
    /// (ticket 32026). The caller must NOT treat `nil` as "alien address" —
    /// unlike signing, where a miss safely fails closed, answering
    /// `false` here triggers a destructive reset of the CrowdNode link.
    static func ownsAddress(_ address: String) -> Bool? {
        ownsAddress(address, using: liveOwnership())
    }

    /// Lossy bridge over `ownership(of:using:)` for callers that only need the
    /// trust decision. Both unknowns become `nil`; anything that must tell them
    /// apart calls `ownership` directly.
    static func ownsAddress(_ address: String, using lookup: OwnershipLookup?) -> Bool? {
        switch ownership(of: address, using: lookup) {
        case .owned: return true
        case .foreign: return false
        case .walletUnavailable, .notFoundWithinBound: return nil
        }
    }

    private static func liveOwnership() -> OwnershipLookup? {
        guard let network = SwiftDashSDKHost.shared.runningNetwork,
              let wallet = SwiftDashSDKHost.shared.wallet else {
            return nil
        }
        return OwnershipLookup(
            isP2PKH: { isP2PKH($0, network: network) },
            derivationPath: { try wallet.findBIP44AddressPath(address: $0) })
    }

    /// Whether `address` is a P2PKH address of `network`. Anything else is the
    /// one input that lets `ownsAddress` answer `false`, so it is exercised
    /// directly by the tests.
    static func isP2PKH(_ address: String, network: Network) -> Bool {
        let paymentNetwork: PaymentNetwork = network == .mainnet ? .mainnet : .testnet
        // A P2SH script is 23 bytes, and P2SH can't be message-signed.
        return ScriptAddressCodec.scriptPubKey(forAddress: address, network: paymentNetwork)?.count == 25
    }
}
