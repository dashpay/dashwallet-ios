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
    @objc
    public class func start() {
        let _ = CrowdNode.shared
    }

    @objc
    public class func restoreState() {
        CrowdNode.shared.restoreState()
    }

    @objc
    public class func isInterrupted() -> Bool {
        CrowdNode.shared.signUpState == .acceptTermsRequired
    }

    @objc
    public class func continueInterrupted() {
        let crowdNode = CrowdNode.shared

        if crowdNode.signUpState == .acceptTermsRequired {
            Task {
                let address = crowdNode.accountAddress
                await crowdNode.signUp(accountAddress: address)
            }
        }
    }

    @objc
    public class func crowdNodeWebsiteUrl() -> URL {
        URL(string: CrowdNode.websiteUrl)!
    }

    @objc
    public class func notificationID() -> String {
        CrowdNode.notificationID
    }

    @objc
    public class func apiOffset() -> UInt64 {
        CrowdNode.apiOffset
    }
}

private let kValidStatus = "valid"
private let kConfirmedStatus = "confirmed"
private let kMessageReceivedStatus = "received"
private let kMessageFailedStatus = "failed"

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
            lhs.rawValue < rhs.rawValue
        }

        var isLinkingInProgress: Bool {
            self == .linking || self == .validating || self == .confirming
        }
    }

    private var cancellableBag = Set<AnyCancellable>()
    private lazy var sendCoinsService = SendCoinsService()
    private lazy var txObserver = TransactionObserver()
    private lazy var webService = CrowdNodeService()
    private let prefs = CrowdNodeDefaults.shared
    private var timer: Timer? = nil

    @Published private(set) var signUpState = SignUpState.notInitiated
    @Published private(set) var onlineAccountState = OnlineAccountState.none
    @Published private(set) var balance: UInt64 = 0
    @Published private(set) var isBalanceLoading = false
    @Published var apiError: Swift.Error? = nil

    var accountAddress: String { prefs.accountAddress ?? "" }
    private(set) var primaryAddress: String? = nil
    private(set) var linkingApiAddress: String? = nil
    private(set) var isOnlineStateRestored = false
    var showNotificationOnResult = false

    var masternodeAPY: Double
    var crowdnodeAPY: Double

    public static let shared: CrowdNode = .init()
    private static let topUpFeeReserve: UInt64 = 10_000

    init() {
        masternodeAPY = MasternodeAPYCalculator.estimatedAPY()
        crowdnodeAPY = masternodeAPY * (1 - prefs.feePercentage)
        print("CrowdNode: masternodeAPY: \(masternodeAPY), crowdnodeAPY: \(crowdnodeAPY)")

        NotificationCenter.default.publisher(for: NSNotification.Name.DWWillWipeWallet)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellableBag)

        NotificationCenter.default.publisher(for: NSNotification.Name.DWCurrentNetworkDidChange)
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellableBag)

        // A runtime wallet switch rebinds every per-wallet fact: CrowdNode state
        // is scoped by the active walletId (see CrowdNodeDefaults), and this
        // singleton caches the previous wallet's account/balance/signup state in
        // memory (plus CrowdNodeDefaults' own `_`-backed value cache). Reload
        // against the now-active wallet so wallet A's CrowdNode balance/account
        // never shows under wallet B. Mirrors SwiftDashSDKContactsService's
        // observer of the same notification.
        NotificationCenter.default.publisher(for: SwiftDashSDKWalletState.activeWalletDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleActiveWalletChanged() }
            .store(in: &cancellableBag)

        $onlineAccountState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let wSelf = self else { return }

                wSelf.timer?.invalidate()
                let fireImmediately = wSelf.isOnlineStateRestored

                switch state {
                case .linking:
                    wSelf.startTrackingLinked(address: wSelf.linkingApiAddress!)
                case .validating:
                    wSelf.startTrackingValidated(address: wSelf.accountAddress, fireImmediately: fireImmediately)
                case .confirming:
                    wSelf.startTrackingConfirmed(address: wSelf.accountAddress, fireImmediately: fireImmediately)
                case .creating:
                    wSelf.startTrackingCreating(address: wSelf.accountAddress, fireImmediately: fireImmediately)
                default:
                    break
                }
            }
            .store(in: &cancellableBag)
    }

    private func topUpAccount(_ accountAddress: String, _ amount: UInt64,
                              sessionAuthSufficient: Bool = false) async throws -> Data {
        // sendCoins broadcasts via SwiftDashSDK and throws on failure, and the
        // follow-up signal send polls the SDK's UTXO set itself before
        // spending the top-up — no extra spendability wait is needed here.
        return try await sendCoinsService.sendCoins(address: accountAddress, amount: amount,
                                                    sessionAuthSufficient: sessionAuthSufficient)
    }
}

// MARK: Restoring state
extension CrowdNode {
    func restoreState() {
        checkAPY()
        
        if signUpState > SignUpState.notStarted {
            // Already started/restored
            return
        }

        DWLogger.log("restoring CrowdNode state")
        signUpState = SignUpState.notStarted
        validatePrefs()

        if tryRestoreSignUp() {
            refreshWithdrawalLimits()
            refreshFees()
            restoreCreatedOnlineAccount(accountAddress)
            return
        }

        var onlineState = prefs.savedOnlineAccountState

        if let address = getOnlineAccountAddress(state: onlineState) {
            prefs.accountAddress = address

            if onlineState == .none {
                onlineState = .linking
            }

            do {
                try tryRestoreLinkedOnlineAccount(state: onlineState, address: address)
                refreshWithdrawalLimits()
                // Linked online accounts don't go through `setFinished`, so their balance was
                // never fetched at restore — only when the user opened the CrowdNode portal.
                // Refresh it proactively so the balance reminder (banner/sheet) can appear after
                // sync without requiring the user to enter CrowdNode. `refreshBalance` self-guards
                // on `signUpState`, so it no-ops for accounts that aren't linked yet.
                // Don't seed from cache: a stale positive `lastKnownBalance` would otherwise drive
                // the balance reminder before the first fresh fetch, surfacing/consuming it even
                // when the server returns 0.
                refreshBalance(seedFromCache: false)
            } catch {
                DWLogger.log("Failure while restoring linked CrowdNode account: \(error.localizedDescription)")
            }
        } else {
            DWLogger.log("CrowdNode: account not found")
        }
    }

    private func tryRestoreSignUp() -> Bool {
        let fullSet = FullCrowdNodeSignUpTxSet()
        TransactionObserver
            .fetchObserved(firstSeenAtOrAfter: FullCrowdNodeSignUpTxSet.januaryFirst2022Epoch)
            .forEach { fullSet.tryInclude($0) }

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
        prefs.accountAddress = address
        DWLogger.log("found finished CrowdNode sign up, account: \(address)")
        signUpState = SignUpState.finished
        refreshBalance(retries: 1)
        setTaxCategories()
    }

    private func setAcceptingTerms(address: String) {
        prefs.accountAddress = address
        DWLogger.log("found accept terms CrowdNode response, account: \(address)")
        signUpState = SignUpState.acceptingTerms
    }

    private func setAcceptTermsRequired(address: String) {
        prefs.accountAddress = address
        DWLogger.log("found accept terms CrowdNode response, account: \(address)")
        signUpState = SignUpState.acceptTermsRequired
    }

    private func setSigningUp(address: String) {
        prefs.accountAddress = address
        DWLogger.log("found signUp CrowdNode request, account: \(address)")
        signUpState = SignUpState.signingUp
    }

    private func validatePrefs() {
        guard let accountAddress = prefs.accountAddress else { return }

        // SDK-native ownership check (BIP44 acct-0 scan — the same one the
        // CrowdNode signer uses). Tri-state: nil ⇒ the SDK wallet isn't up
        // yet, so we can't validate — skip rather than reset a live account;
        // the check reruns on the next restoreState.
        let owns: Bool?
        if Thread.isMainThread {
            owns = MainActor.assumeIsolated { CrowdNodeMessageSigner.ownsAddress(accountAddress) }
        } else {
            var captured: Bool?
            DispatchQueue.main.sync {
                captured = MainActor.assumeIsolated { CrowdNodeMessageSigner.ownsAddress(accountAddress) }
            }
            owns = captured
        }

        switch owns {
        case false:
            DWLogger.log("Found alien address in CrowdNode prefs")
            reset()
        case nil:
            DWLogger.log("CrowdNode prefs validation skipped — SDK wallet not available yet")
        default:
            break
        }
    }

    private func reset() {
        DWLogger.log("CrowdNode reset triggered")
        signUpState = .notStarted
        onlineAccountState = .none
        linkingApiAddress = nil
        primaryAddress = nil
        apiError = nil
        balance = 0
        prefs.resetUserDefaults()
    }

    /// React to a runtime wallet switch: drop the in-memory state cached for the
    /// previous wallet and re-restore from the now-active wallet's per-wallet
    /// defaults. Unlike `reset()`, this does NOT call `prefs.resetUserDefaults()`
    /// — that would erase the newly-active wallet's persisted CrowdNode state.
    /// It only invalidates `CrowdNodeDefaults`' in-memory value cache (so the
    /// next read resolves the new wallet's keys) and re-runs `restoreState()`.
    private func handleActiveWalletChanged() {
        DWLogger.log("CrowdNode reloading for active wallet change")
        prefs.invalidateCache()
        // Clear the previous wallet's published/in-memory state without touching
        // persisted defaults, then re-open the restore path (its `signUpState >
        // .notStarted` guard would otherwise short-circuit the reload).
        signUpState = .notInitiated
        onlineAccountState = .none
        linkingApiAddress = nil
        primaryAddress = nil
        apiError = nil
        balance = 0
        isOnlineStateRestored = false
        restoreState()
    }
    
    private func checkAPY() {
        // Estimated figure at the current SPV tip; recomputing is cheap.
        // TODO(masternode-stats-ffi): use the live virtual masternode count
        // once the upstream stats FFI lands.
        masternodeAPY = MasternodeAPYCalculator.estimatedAPY()
        crowdnodeAPY = masternodeAPY * (1 - prefs.feePercentage)
    }
}

// MARK: Signup
extension CrowdNode {
    func signUp(accountAddress: String) async {
        prefs.accountAddress = accountAddress

        do {
            if signUpState < SignUpState.acceptTermsRequired {
                signUpState = SignUpState.fundingWallet
                let topUpTx = try await topUpAccount(accountAddress, CrowdNode.requiredForSignup,
                                                     sessionAuthSufficient: true)
                DWLogger.log("CrowdNode TopUp tx hash: \(Transaction.displayHex(topUpTx))")

                signUpState = SignUpState.signingUp
                try await makeSignUpRequest(accountAddress)

                signUpState = SignUpState.acceptingTerms
                try await acceptTerms(accountAddress)
            }
            else {
                signUpState = SignUpState.acceptingTerms
                let _ = try await topUpAccount(accountAddress, CrowdNode.requiredForAcceptTerms,
                                               sessionAuthSufficient: true)
                try await acceptTerms(accountAddress)
            }

            notifyIfNeeded(message: NSLocalizedString("Your CrowdNode account is set up and ready to use!", comment: "CrowdNode"))
            signUpState = SignUpState.finished
            refreshBalance()
        }
        catch {
            DWLogger.log("CrowdNode error: \(error)")
            signUpState = SignUpState.error
            apiError = error
        }
    }

    private func makeSignUpRequest(_ accountAddress: String) async throws {
        let requestValue = CrowdNode.apiOffset + ApiCode.signUp.rawValue
        // Capture BEFORE broadcast: the response always postdates the request,
        // and the observer's freshness floor keys off this instant.
        let requestSentAt = Date()
        let signUpTx = try await sendCoinsService.sendCoins(address: CrowdNode.crowdNodeAddress,
                                                            amount: requestValue,
                                                            inputSelector: SingleInputAddressSelector(address: accountAddress),
                                                            sessionAuthSufficient: true)
        DWLogger.log("CrowdNode SignUp tx hash: \(Transaction.displayHex(signUpTx))")

        let successResponse = CrowdNodeResponse(responseCode: ApiCode.pleaseAcceptTerms,
                                                accountAddress: accountAddress)
        let errorResponse = CrowdNodeErrorResponse(errorValue: requestValue,
                                                   accountAddress: accountAddress)

        let responseTx = await txObserver.first(filters: errorResponse, successResponse, after: requestSentAt)
        DWLogger.log("CrowdNode AcceptTerms response tx: \(responseTx.txidHexDisplay)")

        if errorResponse.matches(responseTx) {
            throw CrowdNode.Error.signUp
        }
    }

    private func acceptTerms(_ accountAddress: String) async throws {
        let requestValue = CrowdNode.apiOffset + ApiCode.acceptTerms.rawValue
        let requestSentAt = Date()
        let termsAcceptedTx = try await sendCoinsService.sendCoins(address: CrowdNode.crowdNodeAddress,
                                                                   amount: requestValue,
                                                                   inputSelector: SingleInputAddressSelector(address: accountAddress),
                                                                   sessionAuthSufficient: true)
        DWLogger.log("CrowdNode Terms Accepted tx hash: \(Transaction.displayHex(termsAcceptedTx))")

        let successResponse = CrowdNodeResponse(responseCode: ApiCode.welcomeToApi,
                                                accountAddress: accountAddress)
        let errorResponse = CrowdNodeErrorResponse(errorValue: requestValue,
                                                   accountAddress: accountAddress)

        let responseTx = await txObserver.first(filters: errorResponse, successResponse, after: requestSentAt)
        DWLogger.log("CrowdNode Welcome response tx: \(responseTx.txidHexDisplay)")

        if errorResponse.matches(responseTx) {
            throw CrowdNode.Error.signUp
        }
    }
}

// MARK: Deposits / withdrawals
extension CrowdNode {
    func deposit(amount: UInt64) async throws {
        guard !accountAddress.isEmpty else { return }

        let maxSendable = SwiftDashSDKWalletState.shared.balance?.maxSendable ?? 0
        let addition = amount.addingReportingOverflow(Self.topUpFeeReserve)
        let requiredTopUp = addition.overflow ? UInt64.max : addition.partialValue
        let finalTopUp = min(maxSendable, requiredTopUp)

        // One PIN per deposit action: the top-up (the flow's first send) keeps
        // the default per-send prompt — a successful entry sets
        // DSAuthenticationManager.didAuthenticate — and the deposit signal a
        // moment later rides that session instead of prompting a second time.
        let topUpTx = try await topUpAccount(accountAddress, finalTopUp)
        DWLogger.log("CrowdNode deposit topup tx hash: \(Transaction.displayHex(topUpTx))")

        let requestSentAt = Date()
        let depositTx = try await sendCoinsService.sendCoins(address: CrowdNode.crowdNodeAddress,
                                                             amount: min(maxSendable, amount),
                                                             inputSelector: SingleInputAddressSelector(address: accountAddress),
                                                             sessionAuthSufficient: true)
        DWLogger.log("CrowdNode deposit tx hash: \(Transaction.displayHex(depositTx))")

        Task {
            let successResponse = CrowdNodeResponse(responseCode: ApiCode.depositReceived,
                                                    accountAddress: accountAddress)
            let errorResponse = CrowdNodeErrorResponse(errorValue: amount,
                                                       accountAddress: accountAddress)

            // The freshness floor is what keeps a PREVIOUS deposit's ack row
            // from instantly satisfying this wait on the initial scan.
            let responseTx = await txObserver.first(filters: errorResponse, successResponse, after: requestSentAt)
            DWLogger.log("CrowdNode deposit response tx: \(responseTx.txidHexDisplay)")

            if errorResponse.matches(responseTx) {
                handleError(error: CrowdNode.Error.deposit)
            } else {
                refreshBalance()
            }
        }
    }

    func withdraw(amount: UInt64, signature: String) async throws {
        guard !accountAddress.isEmpty else { return }
        guard amount <= balance else { return }

        try checkWithdrawalLimits(amount)

        DWLogger.log("CrowdNode: request withdrawal")
        let result = try await webService.requestWithdrawal(address: accountAddress, amount: amount, signature: signature)

        if result.messageStatus.lowercased() == kMessageReceivedStatus {
            DWLogger.log("CrowdNode: withdrawal request sent successfully")
            refreshBalance(afterWithdrawal: true)
            updateLastWithdrawalBlock()
        } else {
            DWLogger.log("CrowdNode: sendMessage not received, status: \(String(describing: result.messageStatus)). Result: \(String(describing: result.result))")
            
            if let msg = result.result {
                handleError(error: CrowdNode.Error.messageStatus(error: msg))
            } else {
                handleError(error: CrowdNode.Error.withdraw)
            }
        }
    }

    func calculateWithdrawalPermil(forAmount: UInt64) -> UInt64 {
        let maxPermil = ApiCode.withdrawAll.rawValue

        if balance == 0 {
            return maxPermil
        }

        let permil = UInt64(round(Double(forAmount * maxPermil) / Double(balance)))
        let requestPermil = min(permil, maxPermil)

        return requestPermil
    }

    func hasAnyDeposits() -> Bool {
        guard !accountAddress.isEmpty else { return false }
        let filter = CrowdNodeDepositTx(accountAddress: accountAddress)
        return TransactionObserver.fetchObserved().contains { filter.matches($0) }
    }

    private func checkWithdrawalLimits(_ amount: UInt64) throws {
        // One withdrawal per block: tipHeight is the SPV synced-headers tip
        // (0 only before the client publishes one — the staking UI is gated
        // on syncDone, so a live height is available whenever this runs).
        let tipHeight = SwiftDashSDKSPVCoordinator.shared.tipHeight

        if tipHeight > 0, tipHeight <= prefs.lastWithdrawalBlock {
            throw CrowdNode.Error.withdrawLimit(amount: 0, period: .perBlock)
        }
        
        let perTransactionLimit = getWithdrawalLimit(.perTransaction)

        if amount > perTransactionLimit {
            throw CrowdNode.Error.withdrawLimit(amount: perTransactionLimit, period: .perTransaction)
        }

        let withdrawalsLastHour = getWithdrawalsForTheLast(hours: 1)
        let perHourLimit = getWithdrawalLimit(.perHour)

        if withdrawalsLastHour + amount > perHourLimit {
            throw CrowdNode.Error.withdrawLimit(amount: perHourLimit, period: .perHour)
        }

        let withdrawalsLast24h = getWithdrawalsForTheLast(hours: 24)
        let perDayLimit = getWithdrawalLimit(.perDay)

        if withdrawalsLast24h + amount > perDayLimit {
            throw CrowdNode.Error.withdrawLimit(amount: perDayLimit, period: .perDay)
        }
    }

    private func getWithdrawalsForTheLast(hours: Int) -> UInt64 {
        let now = Date()
        let from = Calendar.current.date(byAdding: .hour, value: -hours, to: now)!

        let filter = CrowdNodeWithdrawalReceivedTx()
            .and(txFilter: TxWithinTimePeriod(from: from, to: now))
        let floor = UInt64(max(0, from.timeIntervalSince1970))

        return TransactionObserver.fetchObserved(firstSeenAtOrAfter: floor)
            .filter { filter.matches($0) }
            .map(\.ownOutputsAmount)
            .reduce(0, +)
    }

    private func updateLastWithdrawalBlock() {
        prefs.lastWithdrawalBlock = SwiftDashSDKSPVCoordinator.shared.tipHeight
    }
}

// MARK: Balance
extension CrowdNode {
    /// - Parameter seedFromCache: When `true` (default) the cached `lastKnownBalance` is published
    ///   immediately so UI (e.g. the CrowdNode portal) shows a value while the fetch is in flight.
    ///   Pass `false` for silent/background refreshes (e.g. restore) where a stale positive cache
    ///   must not drive balance-derived UI such as `CrowdNodeBalanceReminder` before the first
    ///   fresh fetch completes.
    func refreshBalance(retries: Int = 3, afterWithdrawal: Bool = false, seedFromCache: Bool = true) {
        guard !accountAddress.isEmpty && signUpState != .notStarted else { return }

        Task {
            let lastBalance = prefs.lastKnownBalance
            var currentBalance = lastBalance
            if seedFromCache {
                balance = currentBalance
            }
            isBalanceLoading = true

            do {
                for i in 0...retries {
                    if i != 0 {
                        let secondsToWait = UInt64(pow(5.0, Double(i)))
                        try await Task.sleep(nanoseconds: secondsToWait * 1_000_000_000)
                    }

                    let result = try await webService.getBalance(address: accountAddress)
                    let dashNumber = Decimal(result.totalBalance)
                    let duffsNumber = Decimal(kOneDash)
                    let plainAmount = dashNumber * duffsNumber
                    currentBalance = NSDecimalNumber(decimal: plainAmount).uint64Value
                    prefs.lastKnownBalance = currentBalance
                    // Publish the fresh value as soon as it arrives. The loop keeps polling (with
                    // escalating backoff) until the balance *changes* vs. the cached baseline, which
                    // can take minutes; without this, a non-seeded refresh (e.g. restore) wouldn't
                    // surface the real balance — and the balance reminder — until the loop ends.
                    balance = currentBalance

                    var breakDifference: UInt64 = 0

                    if afterWithdrawal {
                        breakDifference = CrowdNode.apiOffset + ApiCode.maxCode().rawValue
                    }

                    if llabs(Int64(lastBalance) - Int64(currentBalance)) > breakDifference {
                        // Balance changed, no need to retry anymore
                        break
                    }
                }
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
        DWLogger.log("CrowdNode error: \(error.errorDescription)")
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
                    prefs.crowdNodeWithdrawalLimitPerTx = perTx
                }

                if let value = limits[WithdrawalLimitPeriod.perHour], let perHour = value {
                    prefs.crowdNodeWithdrawalLimitPerHour = perHour
                }

                if let value = limits[WithdrawalLimitPeriod.perDay], let perDay = value {
                    prefs.crowdNodeWithdrawalLimitPerDay = perDay
                }
            } catch {
                DWLogger.log("CrowdNode refreshWithdrawalLimits error: \(error.localizedDescription)")
            }
        }
    }
    
    private func refreshFees() {
        Task {
            do {
                let feeInfo = try await webService.getFees(address: accountAddress)

                if let value = feeInfo.getNormalFee() {
                    prefs.feePercentage = value.fee / 100
                }
            } catch {
                DWLogger.log("CrowdNode refreshFees error: \(error.localizedDescription)")
            }
        }
    }

    private func getWithdrawalLimit(_ period: WithdrawalLimitPeriod) -> UInt64 {
        switch period {
        case .perTransaction:
            return prefs.crowdNodeWithdrawalLimitPerTx
        case .perHour:
            return prefs.crowdNodeWithdrawalLimitPerHour
        case .perDay:
            return prefs.crowdNodeWithdrawalLimitPerDay
        case .perBlock:
            return 0
        }
    }
}

// MARK: Online account
extension CrowdNode {
    func trackLinkingAccount(address: String) {
        linkingApiAddress = address
        prefs.accountAddress = address
        changeOnlineState(to: .linking)
    }

    func stopTrackingLinked() {
        if signUpState == .notStarted && onlineAccountState <= .linking {
            DWLogger.log("CrowdNode: stopTrackingLinked")
            changeOnlineState(to: .none)

            if let address = linkingApiAddress {
                Task {
                    // One last check just in case
                    try await Task.sleep(nanoseconds: 5 * UInt64(pow(10.0, 9.0)))
                    checkIfAddressIsInUse(address: address)
                }
            }
        }
    }

    func registerEmailForAccount(email: String, signature: String) async throws {
        guard !accountAddress.isEmpty else { return }

        DWLogger.log("CrowdNode: sending signed email message")
        let result = try await webService.registerEmail(address: accountAddress, email: email, signature: signature)

        if result.messageStatus.lowercased() == kMessageReceivedStatus {
            DWLogger.log("CrowdNode: signed email sent successfully")
            prefs.signedEmailMessageId = result.id
            changeOnlineState(to: .creating)
        } else {
            DWLogger.log("CrowdNode: sendMessage not received, status: \(String(describing: result.messageStatus)). Result: \(String(describing: result.result))")
            apiError = CrowdNode.Error.messageStatus(error: result.result ?? "")
        }
    }

    func setOnlineAccountCreated() {
        changeOnlineState(to: .done)
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
            prefs.savedOnlineAccountState = to
        }
    }


    private func tryRestoreLinkedOnlineAccount(state: OnlineAccountState, address: String) throws {
        if let address = prefs.crowdNodePrimaryAddress {
            primaryAddress = address
        }

        switch state {
        case .none:
            break
        case .linking:
            DWLogger.log("CrowdNode: found linking online account in progress, account: \(address), primary: \(String(describing: primaryAddress))")
            checkIfAddressIsInUse(address: address)
        case .creating, .signingUp:
            // This should not happen - this method is reachable only for a linked account case
            throw CrowdNode.Error.restoreLinked(state: state)
        default:
            changeOnlineState(to: state, save: false)
            DWLogger.log("CrowdNode: found online account, state: \(state), account: \(address), primary: \(String(describing: primaryAddress))")
            break
        }
    }

    private func startTrackingLinked(address: String) {
        DWLogger.log("CrowdNode: startTrackingLinked, account: \(address)")
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.checkIfAddressIsInUse(address: address)
        }
        timer.tolerance = 0.5
        self.timer = timer
    }

    private func startTrackingValidated(address: String, fireImmediately: Bool) {
        DWLogger.log("CrowdNode: startTrackingValidated, account: \(address)")
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkAddressStatus(address: address)
        }
        timer.tolerance = 0.5
        self.timer = timer

        if fireImmediately {
            timer.fire()
        }
    }

    private func startTrackingConfirmed(address: String, fireImmediately: Bool) {
        let timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.checkAddressStatus(address: address)
        }
        timer.tolerance = 0.5
        self.timer = timer

        if fireImmediately {
            timer.fire()
        }

        Task {
            DWLogger.log("CrowdNode: startTrackingConfirmed, account: \(address)")

            // First check or wait for the confirmation tx.
            // No need to make web requests if it isn't found.
            let confirmationTx = await waitForApiAddressConfirmation(primaryAddress: primaryAddress!, apiAddress: accountAddress)
            DWLogger.log("CrowdNode: confirmation tx found: \(confirmationTx.txidHexDisplay)")

            if hasDepositConfirmations() {
                // If a deposit confirmation was received, the address has been confirmed already
                changeOnlineState(to: .done)

                if prefs.shouldShowConfirmedNotification {
                    prefs.shouldShowConfirmedNotification = false
                    notifyIfNeeded(message: NSLocalizedString("Your CrowdNode address has been confirmed.", comment: "CrowdNode"))
                }

                return
            }

            // Chain acceptance (IS-lock or mined) was enforced by the gated
            // filter in waitForApiAddressConfirmation — the SDK stand-in for
            // the legacy DashSync account.transactionIsValid gate (stronger:
            // legacy accepted mempool txs).
            let forwardedFilter = CrowdNodeAPIConfirmationTxForwarded()
            if TransactionObserver.fetchObserved().contains(where: { forwardedFilter.matches($0) }) {
                DWLogger.log("CrowdNode: confirmation already forwarded — skipping")
                return
            }

            do {
                let forwardTx = try await sendCoinsService.sendCoins(
                    address: CrowdNode.crowdNodeAddress,
                    amount: CrowdNode.apiConfirmationDashAmount,
                    inputSelector: SingleInputAddressSelector(address: address),
                    adjustAmountDownwards: true,
                    sessionAuthSufficient: true
                )
                DWLogger.log("CrowdNode: forwarded confirmation tx: \(Transaction.displayHex(forwardTx))")
            } catch {
                // Legacy parity: log only — the 20s web poll (checkAddressStatus)
                // is the fallback that completes linking.
                DWLogger.log("CrowdNode: error forwarding confirmation tx: \(error)")
            }
        }
    }

    private func startTrackingCreating(address: String, fireImmediately: Bool) {
        DWLogger.log("CrowdNode: startTrackingCreating, account: \(address)")
        let timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.checkIfEmailRegistered(address: address)
        }
        timer.tolerance = 0.5
        self.timer = timer

        if fireImmediately {
            timer.fire()
        }
    }

    private func checkIfAddressIsInUse(address: String) {
        Task {
            let result = await webService.isAddressInUse(address: address)
            primaryAddress = result.primaryAddress

            if result.isInUse && onlineAccountState <= .linking {
                if primaryAddress == nil {
                    apiError = CrowdNode.Error.missingPrimary
                    changeOnlineState(to: .none)
                } else {
                    prefs.accountAddress = address
                    prefs.crowdNodePrimaryAddress = result.primaryAddress
                    setTaxCategories()
                    changeOnlineState(to: .validating)
                }
            }
        }
    }

    private func checkAddressStatus(address: String) {
        Task {
            let status = await webService.addressStatus(address: address)

            if status.lowercased() == kValidStatus && onlineAccountState != .confirming {
                changeOnlineState(to: .confirming)
                notifyIfNeeded(message: NSLocalizedString("Your CrowdNode address has been validated, but verification is required.", comment: "CrowdNode"))
            } else if status.lowercased() == kConfirmedStatus {
                changeOnlineState(to: .done)

                if prefs.shouldShowConfirmedNotification {
                    prefs.shouldShowConfirmedNotification = false
                    notifyIfNeeded(message: NSLocalizedString("Your CrowdNode address has been confirmed.", comment: "CrowdNode"))
                }
                refreshBalance()
            }
        }
    }

    private func checkIfEmailRegistered(address: String) {
        Task {
            let usingDummyEmail = await webService.isDefaultEmail(address: address)

            if usingDummyEmail {
                // User email isn't set yet. Check the message status in case there is an error
                let messageId = prefs.signedEmailMessageId

                if messageId != -1 {
                    let message = await webService.checkMessageStatus(id: messageId, address: address)

                    if message?.messageStatus.lowercased() == kMessageFailedStatus {
                        // Operation failed
                        apiError = CrowdNode.Error.messageStatus(error: message?.result ?? "")
                        prefs.signedEmailMessageId = -1
                        changeOnlineState(to: .none)
                    }
                }
            } else {
                // Good to go
                changeOnlineState(to: .signingUp)
            }
        }
    }

    private func waitForApiAddressConfirmation(primaryAddress: String, apiAddress: String) async -> ObservedTransaction {
        // Chain-accepted only: the caller forwards money on match, so a
        // mempool-only sighting must not resolve this wait (the gate lives in
        // the filter — the observer's txid dedupe runs after the filters, so
        // the same row re-matches once the persister upgrades its context).
        let filter = CrowdNodeAPIConfirmationTx(primaryAddress: primaryAddress, apiAddress: apiAddress,
                                                requireChainAccepted: true)

        if let tx = TransactionObserver.fetchObserved().first(where: { filter.matches($0) }) {
            return tx
        }
        else {
            // Deep floor instead of the default now−120s: a confirmation row
            // first seen before this wait started (e.g. mempool at restore
            // time) must still match when its context flips to accepted.
            // Safe for this filter — it is unique per link (primary+api
            // pair), and the caller's already-forwarded guard covers a
            // re-link's historic confirmation.
            return await txObserver.first(
                filters: filter,
                after: Date(timeIntervalSince1970: TimeInterval(FullCrowdNodeSignUpTxSet.januaryFirst2022Epoch)))
        }
    }

    private func hasDepositConfirmations() -> Bool {
        let filter = CrowdNodeResponse(responseCode: ApiCode.depositReceived,
                                       accountAddress: accountAddress)

        return TransactionObserver.fetchObserved().contains { filter.matches($0) }
    }

    private func getOnlineAccountAddress(state: OnlineAccountState) -> String? {
        let savedAddress = prefs.accountAddress

        if savedAddress != nil && state != .none {
            return savedAddress
        } else if let confirmationTx = getApiAddressConfirmationTx(),
                  let apiAddress = confirmationTx.ownOutputAddresses.first {
            prefs.accountAddress = apiAddress
            signUpState = .linkedOnline
            prefs.savedOnlineAccountState = .linking

            return apiAddress
        }

        return nil
    }

    private func getApiAddressConfirmationTx() -> ObservedTransaction? {
        let filter = CoinsToAddressTxFilter(coins: CrowdNode.apiConfirmationDashAmount, address: nil) // account address is unknown at this point
        let forwardedConfirmationFilter = CrowdNodeAPIConfirmationTxForwarded()
        let observed = TransactionObserver.fetchObserved()

        // There might be several matching transactions. The real one is the
        // one whose destination CrowdNode forwarded from.
        guard observed.contains(where: { forwardedConfirmationFilter.matches($0) }) else {
            return nil
        }

        return observed.first { confirmationTx in
            guard filter.matches(confirmationTx),
                  let receivedTo = confirmationTx.ownOutputAddresses.first else { return false }
            return forwardedConfirmationFilter.fromAddresses.contains(receivedTo)
        }
    }

    private func restoreCreatedOnlineAccount(_ address: String) {
        let state = prefs.savedOnlineAccountState

        switch state {
        case .none:
            checkIfEmailRegistered(address: address)
        case .creating, .signingUp, .done:
            changeOnlineState(to: state, save: false)
        default:
            break
        }
    }
}

extension CrowdNode {
    private func setTaxCategories() {
        Taxes.shared.mark(address: accountAddress, with: .transferIn)
        Taxes.shared.mark(address: CrowdNode.crowdNodeAddress, with: .transferOut)
    }
}
