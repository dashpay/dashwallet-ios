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

private let kConfirmedStatus = "confirmed"
private let kValidStatus = "valid"

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
    
    enum OnlineAccountState: Int, Comparable {
        case none = 0
        case linking = 1
        case validating = 2
        case confirming = 3
        case creating = 4
        case signingUp = 5
        case done = 6
        
        static func < (lhs: CrowdNode.OnlineAccountState, rhs: CrowdNode.OnlineAccountState) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    private var cancellableBag = Set<AnyCancellable>()
    private lazy var sendCoinsService = SendCoinsService()
    private lazy var txObserver = TransactionObserver()
    private lazy var webService = CrowdNodeService()
    private var timer: Timer? = nil

    @Published private(set) var signUpState = SignUpState.notInitiated
    @Published private(set) var onlineAccountState = OnlineAccountState.none
    @Published private(set) var balance: UInt64 = 0
    @Published private(set) var isBalanceLoading = false
    @Published private(set) var apiError: Swift.Error? = nil

    private(set) var accountAddress = ""
    private(set) var primaryAddress: String? = nil
    private(set) var linkingApiAddress: String? = nil
    private(set) var isOnlineStateRestored: Bool = false
    var showNotificationOnResult = false
    let masternodeAPY = 0.069 // TODO: NMI-832
    lazy var crowdnodeAPY = masternodeAPY * 0.8

    public static let shared: CrowdNode = .init()

    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name.DWWillWipeWallet)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellableBag)
        
        $onlineAccountState.sink { [weak self] state in
            guard let wSelf = self else { return }

            wSelf.timer?.invalidate()
            let initialDelay = wSelf.isOnlineStateRestored ? 0 : 10
            
            switch state {
            case .linking:
                wSelf.startTrackingLinked(address: wSelf.linkingApiAddress!)
            case .validating:
                wSelf.startTrackingValidated(address: wSelf.accountAddress, initialDelay: initialDelay)
            case .confirming:
                wSelf.startTrackingConfirmed(address: wSelf.accountAddress, initialDelay: initialDelay)
                break
            case .creating:
//                startTrackingCreating(accountAddress!!, initialDelay)
                break
                default:
                    break
            }
//            when(status) {
//                                OnlineAccountStatus.Linking -> startTrackingLinked(linkingApiAddress!!)
//                                OnlineAccountStatus.Validating -> startTrackingValidated(accountAddress!!, initialDelay)
//                                OnlineAccountStatus.Confirming -> startTrackingConfirmed(accountAddress!!, initialDelay)
//                                OnlineAccountStatus.Creating -> startTrackingCreating(accountAddress!!, initialDelay)
//                                else -> { }
//                            }
            
        }
        .store(in: &cancellableBag)
    }

    private func topUpAccount(_ accountAddress: String, _ amount: UInt64) async throws -> DSTransaction {
        let topUpTx = try await sendCoinsService.sendCoins(address: accountAddress,
                                                           amount: amount)
        return await txObserver.first(filters: SpendableTransaction(txHashData: topUpTx.txHashData))
    }
}

// MARK: Restoring state
extension CrowdNode {
    func restoreState() {
        if signUpState > SignUpState.notStarted {
            // Already started/restored
            return
        }

        DSLogger.log("restoring CrowdNode state")
        signUpState = SignUpState.notStarted
        
        if tryRestoreSignUp() {
            refreshWithdrawalLimits()
            return
        }
        
        if let address = onlineAccountAddress {
            accountAddress = address
            var onlineState = savedOnlineAccountState
            
            if onlineState == .none {
                onlineState = .linking
            }
            
            do {
                try tryRestoreLinkedOnlineAccount(state: onlineState, address: address)
                refreshWithdrawalLimits()
            } catch {
                DSLogger.log("Failure while restoring linked CrowdNode account: \(error.localizedDescription)")
            }
        }
    }
    
    private func tryRestoreSignUp() -> Bool {
        let fullSet = FullCrowdNodeSignUpTxSet()
        let wallet = DWEnvironment.sharedInstance().currentWallet
        wallet.allTransactions.forEach { transaction in
            fullSet.tryInclude(tx: transaction)
        }

        if let welcomeResponse = fullSet.welcomeToApiResponse {
            precondition(welcomeResponse.toAddress != nil)
            setFinished(address: welcomeResponse.toAddress!)
            return true
        }

        if let acceptTermsResponse = fullSet.acceptTermsResponse {
            precondition(acceptTermsResponse.toAddress != nil)

            if fullSet.acceptTermsRequest == nil {
                setAcceptTermsRequired(address: acceptTermsResponse.toAddress!)
            }
            else {
                setAcceptingTerms(address: acceptTermsResponse.toAddress!)
            }
            return true
        }

        if let signUpRequest = fullSet.signUpRequest {
            precondition(signUpRequest.fromAddresses.first != nil)
            setSigningUp(address: signUpRequest.fromAddresses.first!)
            return true
        }
        
        return false
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

// MARK: Signup
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

// MARK: Deposits / withdrawals
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
        guard amount <= balance else { return }
        
        try checkWithdrawalLimits(amount)
        
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
            let receivedWithdrawalTx = CrowdNodeWithdrawalReceivedTx()
            let errorResponse = CrowdNodeErrorResponse(errorValue: requestValue,
                                                       accountAddress: accountAddress)
            let withdrawalDeniedResponse = CrowdNodeResponse(responseCode: ApiCode.withdrawalDenied,
                                                             accountAddress: accountAddress)

            let responseTx = await txObserver.first(filters: errorResponse, withdrawalDeniedResponse, receivedWithdrawalTx)
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
    
    private func checkWithdrawalLimits(_ amount: UInt64) throws {
        let perTransactionLimit = getWithdrawalLimit(.perTransaction)
        
        if amount > perTransactionLimit {
            throw CrowdNode.Error.withdrawLimit(amount: perTransactionLimit, period: .perTransaction)
        }
        
        let withdrawalsLastHour = getWithdrawalsForTheLast(hours: 1)
        print("CrowdNode: withdrawalsLastHour: \(withdrawalsLastHour)")
        let perHourLimit = getWithdrawalLimit(.perHour)

        if withdrawalsLastHour + amount > perHourLimit {
            throw CrowdNode.Error.withdrawLimit(amount: perHourLimit, period: .perHour)
        }
        
        let withdrawalsLast24h = getWithdrawalsForTheLast(hours: 24)
        print("CrowdNode: withdrawalsLast24h: \(withdrawalsLast24h)")
        let perDayLimit = getWithdrawalLimit(.perDay)

        if withdrawalsLast24h + amount > perDayLimit {
            throw CrowdNode.Error.withdrawLimit(amount: perDayLimit, period: .perDay)
        }
    }
    
    func getWithdrawalsForTheLast(hours: Int) -> UInt64 {
        let now = Date()
        let from = Calendar.current.date(byAdding: .hour, value: -hours, to: now)!

        let wallet = DWEnvironment.sharedInstance().currentWallet
        let filter = CrowdNodeWithdrawalReceivedTx()
            .and(txFilter: TxWithinTimePeriod(from: from, to: now))
        let withdrawals = wallet.allTransactions.filter { tx in filter.matches(tx: tx) }
        let chain = DWEnvironment.sharedInstance().currentChain
        
        return withdrawals.compactMap { tx in chain.amountReceived(from: tx) }.reduce(0, +)
    }
}

// MARK: Balance
extension CrowdNode {
    func refreshBalance(retries: Int = 3, afterWithdrawal: Bool = false) {
        guard !accountAddress.isEmpty && signUpState != .notStarted else { return }

        Task {
            let lastBalance = lastKnownBalance
            var currentBalance = lastBalance
            balance = currentBalance
            isBalanceLoading = true

            do {
                for i in 0...retries {
                    if i != 0 {
                        let secondsToWait = UInt64(pow(5.0, Double(i)))
                        try await Task.sleep(nanoseconds: secondsToWait * 1_000_000_000)
                    }

                    let result = try await webService.getBalance(address: accountAddress)
                    let dashNumber = Decimal(result.totalBalance)
                    let duffsNumber = Decimal(DUFFS)
                    let plainAmount = dashNumber * duffsNumber
                    currentBalance = NSDecimalNumber(decimal: plainAmount).uint64Value
                    lastKnownBalance = currentBalance

                    var breakDifference: UInt64 = 0

                    if afterWithdrawal {
                        breakDifference = CrowdNode.apiOffset + ApiCode.maxCode().rawValue
                    }

                    if llabs(Int64(lastBalance) - Int64(currentBalance)) > breakDifference {
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

// MARK: Errors / Notifications
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

// MARK: Withdrawal limits
extension CrowdNode {
    private func refreshWithdrawalLimits() {
        Task {
            do {
                let limits = try await webService.getWithdrawalLimits(address: accountAddress)
            
                if let value = limits[WithdrawalLimitPeriod.perTransaction], let perTx = value {
                    crowdNodeWithdrawalLimitPerTx = perTx
                }
                
                if let value = limits[WithdrawalLimitPeriod.perHour], let perHour = value {
                    crowdNodeWithdrawalLimitPerHour = perHour
                }
                
                if let value = limits[WithdrawalLimitPeriod.perDay], let perDay = value {
                    crowdNodeWithdrawalLimitPerDay = perDay
                }
            } catch {
                DSLogger.log("CrowdNode refreshWithdrawalLimits error: \(error.localizedDescription)")
            }
        }
    }
    
    private func getWithdrawalLimit(_ period: WithdrawalLimitPeriod) -> UInt64 {
        switch period {
        case .perTransaction:
            return crowdNodeWithdrawalLimitPerTx
        case .perHour:
            return crowdNodeWithdrawalLimitPerHour
        case .perDay:
            return crowdNodeWithdrawalLimitPerDay
        }
    }
}

// MARK: Online account
extension CrowdNode {
    func trackLinkingAccount(address: String) {
        linkingApiAddress = address
        onlineAccountAddress = address
        changeOnlineState(to: .linking)
    }
    
    private func changeOnlineState(to: OnlineAccountState, save: Bool = true) {
        if signUpState != .finished {
            if to < .validating {
                signUpState = .notStarted
            } else {
                signUpState = .linkedOnline
            }
        }
        
        if onlineAccountState == .none {
            isOnlineStateRestored = true
        }
        
        onlineAccountState = to
        
        if save {
            savedOnlineAccountState = to
        }
    }
    
    
    private func tryRestoreLinkedOnlineAccount(state: OnlineAccountState, address: String) throws {
        if let address = crowdNodePrimaryAddress {
            primaryAddress = address
        }
        
        switch state {
        case .none:
            break
        case .linking:
            DSLogger.log("CrowdNode: found linking online account in progress, account: \(address), primary: \(String(describing: primaryAddress))")
//            checkIfAddressIsInUse(address) TODO:
        case .creating, .signingUp:
            // This should not happen - this method is reachable only for a linked account case
            throw CrowdNode.Error.restoreLinked(state: state)
        default:
            changeOnlineState(to: state, save: false)
            DSLogger.log("CrowdNode: found online account, state: \(state), account: \(address), primary: \(String(describing: primaryAddress))")
            break
        }
    }
    
    private func startTrackingLinked(address: String) {
        DSLogger.log("CrowdNode: startTrackingLinked, account: \(address)")
        let context = ["address": address]
        let timer = Timer(fireAt: Date().addingTimeInterval(5), interval: 2, target: self, selector: #selector(checkIfAddressIsInUse), userInfo: context, repeats: true)
        timer.tolerance = 0.5
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }
    
    private func startTrackingValidated(address: String, initialDelay: Int) {
        DSLogger.log("CrowdNode: startTrackingValidated, account: \(address)")
        let context = ["address": address]
        let timer = Timer(fireAt: Date().addingTimeInterval(TimeInterval(initialDelay)), interval: 30, target: self, selector: #selector(checkAddressStatus), userInfo: context, repeats: true)
        timer.tolerance = 0.5
        RunLoop.current.add(timer, forMode: .common)
        self.timer = timer
    }
    
    private func startTrackingConfirmed(address: String, initialDelay: Int) {
        Task {
            DSLogger.log("CrowdNode: startTrackingConfirmed, account: \(address)")
            // First check or wait for the confirmation tx.
            // No need to make web requests if it isn't found.
            
            let confirmationTx = await waitForApiAddressConfirmation(accountAddress: accountAddress)
            DSLogger.log("CrowdNode: confirmation tx found: \(confirmationTx.txHashData)")
            
            if hasDepositConfirmations() {
                // If a deposit confirmation was received, the address has been confirmed already
                changeOnlineState(to: .done)
                notifyIfNeeded(message: NSLocalizedString("Your CrowdNode address has been confirmed.", comment: "CrowdNode"))
                return
            }
            
            let context = ["address": address]
            let timer = Timer(fireAt: Date().addingTimeInterval(TimeInterval(initialDelay)), interval: 30, target: self, selector: #selector(checkAddressStatus), userInfo: context, repeats: true)
            timer.tolerance = 0.5
            RunLoop.current.add(timer, forMode: .common)
            self.timer = timer
        }
    }
    
    @objc private func checkIfAddressIsInUse(timer: Timer) async {
        guard let context = timer.userInfo as? [String: String] else { return }
        
        let address = context["address", default: ""]
        let result = await webService.isAddressInUse(address: address)
        primaryAddress = result.primaryAddress
            
        if result.isInUse && onlineAccountState <= .linking {
            if primaryAddress == nil {
                apiError = CrowdNode.Error.missingPrimary
                changeOnlineState(to: .none)
            } else {
                accountAddress = address
                onlineAccountAddress = address
                crowdNodePrimaryAddress = address
                // TODO: tax category
                changeOnlineState(to: .validating)
            }
        }
    }
    
    @objc private func checkAddressStatus(timer: Timer) async {
        guard let context = timer.userInfo as? [String: String] else { return }
        
        let address = context["address", default: ""]
        let status = await webService.addressStatus(address: address)
        
        if status.lowercased() == kValidStatus && onlineAccountState != .confirming {
            changeOnlineState(to: .confirming)
            notifyIfNeeded(message: NSLocalizedString("Your CrowdNode address has been validated, but verification is required.", comment: "CrowdNode"))
        } else if status.lowercased() == kConfirmedStatus {
            changeOnlineState(to: .done)
            notifyIfNeeded(message: NSLocalizedString("Your CrowdNode address has been confirmed.", comment: "CrowdNode"))
            refreshBalance()
        }
    }
    
    private func waitForApiAddressConfirmation(accountAddress: String) async -> DSTransaction {
        let filter = CrowdNodeAPIConfirmationTx(address: accountAddress)
        let wallet = DWEnvironment.sharedInstance().currentWallet
        
        if let tx = wallet.allTransactions.first(where: { filter.matches(tx: $0) }) {
            return tx
        }
        else {
            return await txObserver.first(filters: filter)
        }
    }
    
    private func hasDepositConfirmations() -> Bool {
        let wallet = DWEnvironment.sharedInstance().currentWallet
        let filter = CrowdNodeResponse(responseCode: ApiCode.depositReceived,
                                       accountAddress: accountAddress)
        
        return wallet.allTransactions.contains { filter.matches(tx: $0) }
    }
}
