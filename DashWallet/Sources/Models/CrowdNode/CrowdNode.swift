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

import BackgroundTasks
import Combine

// MARK: - CrowdNodeObjcWrapper

@objc
public class CrowdNodeObjcWrapper: NSObject {
    @objc public class func restoreState() {
        CrowdNode.shared.restoreState()
    }

    @objc public class func isInterrupted() -> Bool {
        CrowdNode.shared.signUpState == .acceptTermsRequired
    }

    @objc public class func continueInterrupted() {
        let crowdNode = CrowdNode.shared

        if crowdNode.signUpState == .acceptTermsRequired {
            Task {
                let address = crowdNode.accountAddress
                await crowdNode.signUp(accountAddress: address)
            }
        }
    }

    @objc public class func crowdNodeWebsiteUrl() -> URL {
        URL(string: CrowdNode.websiteUrl)!
    }

    @objc public class func notificationID() -> String {
        CrowdNode.notificationID
    }

    @objc public class func apiOffset() -> UInt64 {
        CrowdNode.apiOffset
    }
}

// MARK: - CrowdNode

public final class CrowdNode {
    enum SignUpState: Comparable {
        case notInitiated
        case notStarted
        // Create New Account
        case fundingWallet
        case signingUp
        case acceptTermsRequired
        case acceptingTerms
        case finished
        case error
        // Link Existing Account
        case linkedOnline
    }

    private var cancellableBag = Set<AnyCancellable>()
    private lazy var sendCoinsService = SendCoinsService()
    private lazy var txObserver = TransactionObserver()
    private lazy var crowdNodeWebService = CrowdNodeService()

    @Published private(set) var signUpState = SignUpState.notInitiated
    @Published private(set) var balance: UInt64 = 0
    @Published private(set) var isBalanceLoading = false
    @Published private(set) var apiError: Swift.Error? = nil

    private(set) var accountAddress = ""
    var showNotificationOnResult = false

    let masternodeAPY: Double
    let crowdnodeAPY: Double

    public static let shared: CrowdNode = .init()

    init() {
        masternodeAPY = DWEnvironment.sharedInstance().apy.doubleValue
        crowdnodeAPY = masternodeAPY * 0.85

        NotificationCenter.default.publisher(for: NSNotification.Name.DWWillWipeWallet)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellableBag)
    }

    private func topUpAccount(_ accountAddress: String, _ amount: UInt64) async throws -> DSTransaction {
        let topUpTx = try await sendCoinsService.sendCoins(address: accountAddress,
                                                           amount: amount)
        return await txObserver.first(filters: SpendableTransaction(txHashData: topUpTx.txHashData))
    }
}

// Restoring state
extension CrowdNode {
    func restoreState() {
        if signUpState > SignUpState.notStarted {
            // Already started/restored
            return
        }

        DSLogger.log("restoring CrowdNode state")
        signUpState = SignUpState.notStarted
        let fullSet = FullCrowdNodeSignUpTxSet()
        let wallet = DWEnvironment.sharedInstance().currentWallet
        wallet.allTransactions.forEach { transaction in
            fullSet.tryInclude(tx: transaction)
        }

        if let welcomeResponse = fullSet.welcomeToApiResponse {
            precondition(welcomeResponse.toAddress != nil)
            setFinished(address: welcomeResponse.toAddress!)
            return
        }

        if let acceptTermsResponse = fullSet.acceptTermsResponse {
            precondition(acceptTermsResponse.toAddress != nil)

            if fullSet.acceptTermsRequest == nil {
                setAcceptTermsRequired(address: acceptTermsResponse.toAddress!)
            }
            else {
                setAcceptingTerms(address: acceptTermsResponse.toAddress!)
            }
            return
        }

        if let signUpRequest = fullSet.signUpRequest {
            precondition(signUpRequest.fromAddresses.first != nil)
            setSigningUp(address: signUpRequest.fromAddresses.first!)
        }
    }

    private func setFinished(address: String) {
        accountAddress = address
        DSLogger.log("found finished CrowdNode sign up, account: \(address)")
        signUpState = SignUpState.finished
        refreshBalance(retries: 1)
        // TODO: tax category
    }

    private func setAcceptingTerms(address: String) {
        accountAddress = address
        DSLogger.log("found accept terms CrowdNode response, account: \(address)")
        signUpState = SignUpState.acceptingTerms
    }

    private func setAcceptTermsRequired(address: String) {
        accountAddress = address
        DSLogger.log("found accept terms CrowdNode response, account: \(address)")
        signUpState = SignUpState.acceptTermsRequired
    }

    private func setSigningUp(address: String) {
        accountAddress = address
        DSLogger.log("found signUp CrowdNode request, account: \(address)")
        signUpState = SignUpState.signingUp
    }

    private func reset() {
        DSLogger.log("CrowdNode reset triggered")
        signUpState = .notStarted
        accountAddress = ""
        apiError = nil
    }
}

// Signup
extension CrowdNode {
    func signUp(accountAddress: String) async {
        self.accountAddress = accountAddress

        do {
            if signUpState < SignUpState.acceptTermsRequired {
                signUpState = SignUpState.fundingWallet
                let topUpTx = try await topUpAccount(accountAddress, CrowdNode.requiredForSignup)
                DSLogger.log("CrowdNode TopUp tx hash: \(topUpTx.txHashHexString)")

                signUpState = SignUpState.signingUp
                let (signUpTx, acceptTermsResponse) = try await makeSignUpRequest(accountAddress, [topUpTx])

                signUpState = SignUpState.acceptingTerms
                let _ = try await acceptTerms(accountAddress, [signUpTx, acceptTermsResponse])
            }
            else {
                signUpState = SignUpState.acceptingTerms
                let topUpTx = try await topUpAccount(accountAddress, CrowdNode.requiredForAcceptTerms)
                let _ = try await acceptTerms(accountAddress, [topUpTx])
            }

            notifyIfNeeded(message: NSLocalizedString("Your CrowdNode account is set up and ready to use!", comment: "CrowdNode"))
            signUpState = SignUpState.finished
            refreshBalance()
        }
        catch {
            DSLogger.log("CrowdNode error: \(error)")
            signUpState = SignUpState.error
            apiError = error
        }
    }

    private func makeSignUpRequest(_ accountAddress: String,
                                   _ inputs: [DSTransaction]) async throws -> (req: DSTransaction, resp: DSTransaction) {
        let requestValue = CrowdNode.apiOffset + ApiCode.signUp.rawValue
        let signUpTx = try await sendCoinsService.sendCoins(address: CrowdNode.crowdNodeAddress,
                                                            amount: requestValue,
                                                            inputSelector: SingleInputAddressSelector(candidates: inputs,
                                                                                                      address: accountAddress))
        DSLogger.log("CrowdNode SignUp tx hash: \(signUpTx.txHashHexString)")

        let successResponse = CrowdNodeResponse(responseCode: ApiCode.pleaseAcceptTerms,
                                                accountAddress: accountAddress)
        let errorResponse = CrowdNodeErrorResponse(errorValue: requestValue,
                                                   accountAddress: accountAddress)

        let responseTx = await txObserver.first(filters: errorResponse, successResponse)
        DSLogger.log("CrowdNode AcceptTerms response tx hash: \(responseTx.txHashHexString)")

        if errorResponse.matches(tx: responseTx) {
            throw CrowdNode.Error.signUp
        }

        return (req: signUpTx, resp: responseTx)
    }

    private func acceptTerms(_ accountAddress: String,
                             _ inputs: [DSTransaction]) async throws -> (req: DSTransaction, resp: DSTransaction) {
        let requestValue = CrowdNode.apiOffset + ApiCode.acceptTerms.rawValue
        let termsAcceptedTx = try await sendCoinsService.sendCoins(address: CrowdNode.crowdNodeAddress,
                                                                   amount: requestValue,
                                                                   inputSelector: SingleInputAddressSelector(candidates: inputs,
                                                                                                             address: accountAddress))
        DSLogger.log("CrowdNode Terms Accepted tx hash: \(termsAcceptedTx.txHashHexString)")

        let successResponse = CrowdNodeResponse(responseCode: ApiCode.welcomeToApi,
                                                accountAddress: accountAddress)
        let errorResponse = CrowdNodeErrorResponse(errorValue: requestValue,
                                                   accountAddress: accountAddress)

        let responseTx = await txObserver.first(filters: errorResponse, successResponse)
        DSLogger.log("CrowdNode Welcome response tx hash: \(responseTx.txHashHexString)")

        if errorResponse.matches(tx: responseTx) {
            throw CrowdNode.Error.signUp
        }

        return (req: termsAcceptedTx, resp: responseTx)
    }
}

// Deposits / withdrawals
extension CrowdNode {
    func deposit(amount: UInt64) async throws {
        guard !accountAddress.isEmpty else { return }

        let account = DWEnvironment.sharedInstance().currentAccount
        let requiredTopUp = amount + TX_FEE_PER_INPUT
        let finalTopUp = min(account.maxOutputAmount, requiredTopUp)

        let topUpTx = try await topUpAccount(accountAddress, finalTopUp)
        DSLogger.log("CrowdNode deposit topup tx hash: \(topUpTx.txHashHexString)")

        let depositTx = try await sendCoinsService.sendCoins(address: CrowdNode.crowdNodeAddress,
                                                             amount: min(account.maxOutputAmount, amount),
                                                             inputSelector: SingleInputAddressSelector(candidates: [topUpTx],
                                                                                                       address: accountAddress))
        DSLogger.log("CrowdNode deposit tx hash: \(depositTx.txHashHexString)")

        Task {
            let successResponse = CrowdNodeResponse(responseCode: ApiCode.depositReceived,
                                                    accountAddress: accountAddress)
            let errorResponse = CrowdNodeErrorResponse(errorValue: amount,
                                                       accountAddress: accountAddress)

            let responseTx = await txObserver.first(filters: errorResponse, successResponse)
            DSLogger.log("CrowdNode deposit response tx hash: \(responseTx.txHashHexString)")

            if errorResponse.matches(tx: responseTx) {
                handleError(error: CrowdNode.Error.deposit)
            } else {
                refreshBalance()
            }
        }
    }

    func withdraw(amount: UInt64) async throws {
        guard !accountAddress.isEmpty else { return }
        let account = DWEnvironment.sharedInstance().currentAccount

        let maxPermil = ApiCode.withdrawAll.rawValue
        let permil = UInt64(round(Double(amount * maxPermil) / Double(balance)))
        let requestPermil = min(permil, maxPermil)
        let requestValue = CrowdNode.apiOffset + UInt64(requestPermil)
        let requiredTopUp = requestValue + TX_FEE_PER_INPUT
        let finalTopUp = min(account.maxOutputAmount, requiredTopUp)

        let topUpTx = try await topUpAccount(accountAddress, finalTopUp)
        DSLogger.log("CrowdNode withdraw topup tx hash: \(topUpTx.txHashHexString)")

        let withdrawTx = try await sendCoinsService.sendCoins(address: CrowdNode.crowdNodeAddress,
                                                              amount: requestValue,
                                                              inputSelector: SingleInputAddressSelector(candidates: [topUpTx],
                                                                                                        address: accountAddress))
        DSLogger.log("CrowdNode withdraw tx hash: \(withdrawTx.txHashHexString)")

        Task {
            let successResponse = CrowdNodeResponse(responseCode: ApiCode.withdrawalQueue,
                                                    accountAddress: accountAddress)
            let errorResponse = CrowdNodeErrorResponse(errorValue: requestValue,
                                                       accountAddress: accountAddress)
            let withdrawalDeniedResponse = CrowdNodeResponse(responseCode: ApiCode.withdrawalDenied,
                                                             accountAddress: accountAddress)

            let responseTx = await txObserver.first(filters: errorResponse, withdrawalDeniedResponse, successResponse)
            DSLogger.log("CrowdNode withdraw response tx hash: \(responseTx.txHashHexString)")

            if errorResponse.matches(tx: responseTx) || withdrawalDeniedResponse.matches(tx: responseTx) {
                handleError(error: CrowdNode.Error.withdraw)
            } else {
                refreshBalance(afterWithdrawal: true)
            }
        }
    }

    func hasAnyDeposits() -> Bool {
        guard !accountAddress.isEmpty else { return false }

        let wallet = DWEnvironment.sharedInstance().currentWallet
        let filter = CrowdNodeDepositTx(accountAddress: accountAddress)

        return wallet.allTransactions.contains {
            tx in filter.matches(tx: tx)
        }
    }
}

// Balance
extension CrowdNode {
    func refreshBalance(retries: Int = 3, afterWithdrawal: Bool = false) {
        guard !accountAddress.isEmpty && signUpState != .notStarted else { return }

        Task {
            let lastKnownBalance = DWGlobalOptions.sharedInstance().lastKnownCrowdNodeBalance
            var currentBalance = UInt64(lastKnownBalance)
            balance = currentBalance
            isBalanceLoading = true

            do {
                for i in 0...retries {
                    if i != 0 {
                        let secondsToWait = UInt64(pow(5.0, Double(i)))
                        try await Task.sleep(nanoseconds: secondsToWait * 1_000_000_000)
                    }

                    let result = try await crowdNodeWebService.getCrowdNodeBalance(address: accountAddress)
                    let dashNumber = Decimal(result.totalBalance)
                    let duffsNumber = Decimal(DUFFS)
                    let plainAmount = dashNumber * duffsNumber
                    currentBalance = NSDecimalNumber(decimal: plainAmount).uint64Value
                    DWGlobalOptions.sharedInstance().lastKnownCrowdNodeBalance = currentBalance

                    var breakDifference: UInt64 = 0

                    if afterWithdrawal {
                        breakDifference = CrowdNode.apiOffset + ApiCode.maxCode().rawValue
                    }

                    if llabs(Int64(lastKnownBalance) - Int64(currentBalance)) > breakDifference {
                        // Balance changed, no need to retry anymore
                        break
                    }
                }
            } catch {
                DSLogger.log("CrowdNode balance error: \((error as! HTTPClientError).localizedDescription)")
            }

            balance = currentBalance
            isBalanceLoading = false
        }
    }
}

// Errors / Notifications
extension CrowdNode {
    private func handleError(error: CrowdNode.Error) {
        apiError = error
        notifyIfNeeded(message: error.errorDescription)
        DSLogger.log("CrowdNode error: \(error.errorDescription)")
    }

    private func notifyIfNeeded(message: String) {
        guard showNotificationOnResult &&
            DWGlobalOptions.sharedInstance().localNotificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.body = message
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: CrowdNode.notificationID, content: content, trigger: nil)
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request)
    }
}
