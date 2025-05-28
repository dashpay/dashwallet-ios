//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

private let ALLOW_CONTESTED_USERNAMES_WITHOUT_INVITE = false

struct CreateUsernameUIState {
    var lengthRule: UsernameValidationRuleResult
    var allowedCharactersRule: UsernameValidationRuleResult
    var costRule: UsernameValidationRuleResult
    var usernameBlockedRule: UsernameValidationRuleResult
    var contestedAllowed: Bool
    var hasInvite: Bool
    var isInvitationMixed: Bool
    var isInvitationForContested: Bool
    var requiredDash: UInt64
    var canContinue: Bool
    
    init(lengthRule: UsernameValidationRuleResult, allowedCharactersRule: UsernameValidationRuleResult, costRule: UsernameValidationRuleResult, usernameBlockedRule: UsernameValidationRuleResult, contestedAllowed: Bool, hasInvite: Bool, isInvitationMixed: Bool, isInvitationForContested: Bool, requiredDash: UInt64, canContinue: Bool) {
        self.lengthRule = lengthRule
        self.allowedCharactersRule = allowedCharactersRule
        self.costRule = costRule
        self.usernameBlockedRule = usernameBlockedRule
        self.contestedAllowed = contestedAllowed
        self.hasInvite = hasInvite
        self.isInvitationMixed = isInvitationMixed
        self.isInvitationForContested = isInvitationForContested
        self.requiredDash = requiredDash
        self.canContinue = canContinue
    }
    
    init() {
        self.lengthRule = .empty
        self.allowedCharactersRule = .empty
        self.costRule = .hidden
        self.usernameBlockedRule = .hidden
        self.contestedAllowed = ALLOW_CONTESTED_USERNAMES_WITHOUT_INVITE
        self.hasInvite = false
        self.isInvitationMixed = false
        self.isInvitationForContested = false
        self.requiredDash = DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        self.canContinue = false
    }
}

@MainActor
class CreateUsernameViewModel: ObservableObject {
    private var cancellableBag = Set<AnyCancellable>()
    private let dao: UsernameRequestsDAO = UsernameRequestsDAOImpl.shared
    private let prefs = UsernamePrefs.shared
    private let illegalChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-").inverted
    static let shared = CreateUsernameViewModel()
    
    var hasUsernameRequest: Bool {
        prefs.requestedUsernameId != nil
    }
    
    var shouldRequestPayment: Bool {
        get { !prefs.alreadyPaid }
        set { prefs.alreadyPaid = !newValue }
    }
    
    @Published var uiState = CreateUsernameUIState()
    @Published var username: String = ""
    @Published private(set) var currentUsernameRequest: UsernameRequest? = nil
    @Published private(set) var hasMinimumRequiredBalance = false
    @Published private(set) var hasRecommendedBalance = false
    @Published private(set) var balance: String = ""
    
    var minimumRequiredBalance: String {
        return DWDP_MIN_BALANCE_TO_CREATE_USERNAME.dashAmount.formattedDashAmountWithoutCurrencySymbol
    }
    
    var recommendedBalance: String {
        return DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME.dashAmount.formattedDashAmountWithoutCurrencySymbol
    }
    
    var minimumRequiredBalanceFiat: String {
        let fiat: String

        if let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: DWDP_MIN_BALANCE_TO_CREATE_USERNAME.dashAmount, to: App.fiatCurrency) {
            fiat = NumberFormatter.fiatFormatter.string(from: fiatAmount as NSNumber)!
        } else {
            fiat = NSLocalizedString("Syncing…", comment: "Balance")
        }

        return fiat
    }
    
    init() {
        $username
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.validateUsername(username: text)
            }
            .store(in: &cancellableBag)
        
        observeBalance()
    }
    
    func hasRequests(for username: String) async -> Bool {
        return await dao.get(byUsername: username) != nil
    }
    
    func submitUsernameRequest(withProve link: URL?) async -> Bool {
        do {
            // TODO: MOCK_DASHPAY simulation of a request. Remove when not needed
            // dashPayModel.createUsername(username, invitation: invitationURL)
            
            let now = Date().timeIntervalSince1970
            let identityData = withUnsafeBytes(of: UUID().uuid) { Data($0) }
            let identity = (identityData as NSData).base58String()
            let usernameRequest = UsernameRequest(requestId: UUID().uuidString, username: username, createdAt: Int64(now), identity: "\(identity)\(identity)", link: link?.absoluteString, votes: 0, blockVotes: 0, isApproved: false)
            
            await dao.create(dto: usernameRequest)
            prefs.requestedUsernameId = usernameRequest.requestId
            UsernamePrefs.shared.joinDashPayDismissed = false // TODO: MOCK_DASHPAY remove
            
            let oneSecond = TimeInterval(1_000_000_000)
            let delay = UInt64(oneSecond * 2)
            try await Task.sleep(nanoseconds: delay)
            
            return true
        } catch {
            return false
        }
    }
    
    func fetchUsernameRequestData() {
        if let id = prefs.requestedUsernameId {
            Task {
                currentUsernameRequest = await dao.get(byRequestId: id)
                username = currentUsernameRequest?.username ?? ""
            }
        }
    }
    
    func cancelRequest() {
        if let requestId = prefs.requestedUsernameId {
            Task {
                currentUsernameRequest = nil
                username = ""
                await dao.delete(by: requestId)
                prefs.requestedUsernameId = nil
            }
        }
    }
    
    func updateRequest(with link: URL) {
        Task {
            if var usernameRequest = currentUsernameRequest {
                usernameRequest.link = link.absoluteString
                await dao.update(dto: usernameRequest)
                currentUsernameRequest = usernameRequest
            }
        }
    }
    
    func checkAssetLockTx(_ tx: DSTransaction) {
        Task {
            uiState.isInvitationMixed = await isInvitationMixed(assetLockTx: tx)
            uiState.isInvitationForContested = await invitationAmount(assetLockTx: tx) >= DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME
            uiState.hasInvite = true
            uiState.contestedAllowed = uiState.isInvitationForContested
            uiState.costRule = .hidden
        }
    }
    
    private func isInvitationMixed(assetLockTx: DSTransaction) async -> Bool {
        guard let coreNetworkService = DWEnvironment.sharedInstance().currentChain.chainManager?.dapiClient.dapiCoreNetworkService else { return false }
        let inputTxes: [Data: DSTransaction] = [:]
        
        return assetLockTx.inputs.map { input in
            var hash = input.inputHash
            let hashData = Data(bytes: &hash.u8, count: 32)
            let tx = inputTxes[hashData] //?? (await coreNetworkService.getTransactionWithHash(input.inputHash)) // TODO MOCK_DASHPAY: implement async version
            guard let tx = tx else { return UInt64(0) }
            
            let output = tx.outputs[Int(input.index)]
            return output.amount
        }.allSatisfy { amount in
            DSCoinJoinManager.isDenominatedAmount(amount)
        }
    }
    
    private func invitationAmount(assetLockTx: DSTransaction) async -> UInt64 {
// TODO MOCK_DASHPAY: adapt for DashSync
        
//        return inviteAssetLockTx.value?.let {
//          it.assetLockPayload.creditOutputs?.find { transactionOutput ->
//              if (ScriptPattern.isP2PKH(transactionOutput.scriptPubKey)) {
//                  it.assetLockPublicKey.pubKeyHash.contentEquals(
//                      ScriptPattern.extractHashFromP2PKH(transactionOutput.scriptPubKey)
//                  )
//              } else {
//                  false
//              }
//          }?.value ?: Coin.ZERO
//      } ?: Coin.ZERO
        
        return DWDP_MIN_BALANCE_TO_CREATE_USERNAME
    }
    
    private func validateUsername(username: String) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !username.isEmpty else {
            let hasInvite = uiState.hasInvite
            let isMixed = uiState.isInvitationMixed
            let isContested = uiState.isInvitationForContested
            let contestedAllowed = uiState.contestedAllowed
            
            uiState = CreateUsernameUIState()
            uiState.hasInvite = hasInvite
            uiState.isInvitationMixed = isMixed
            uiState.isInvitationForContested = isContested
            uiState.contestedAllowed = contestedAllowed
            return
        }
        
        let isContestable = isUsernameContestable(username: username)
        // Disable contested usernames if no invite and the constant is false
        let isContested = if ALLOW_CONTESTED_USERNAMES_WITHOUT_INVITE {
            isContestable // TODO: MOCK_DASHPAY
        } else {
            uiState.hasInvite ? isContestable : false
        }
        let lengthValid = isLengthValid(username: username)
        let allowedCharactersRuleValid = allowedCharactersRuleValid(username: username)
        let requiredCost = isContested ? DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME : DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        let balance = DWEnvironment.sharedInstance().currentWallet.balance
        let hasEnoughBalance = balance >= requiredCost
        let isAffordable = uiState.isInvitationForContested || (uiState.hasInvite && !isContested) || hasEnoughBalance
        
        // Treat no-invite scenario like non-contested invite for validation rules
        let shouldUseRelaxedValidation = (uiState.hasInvite && !uiState.isInvitationForContested) || (!uiState.hasInvite && !ALLOW_CONTESTED_USERNAMES_WITHOUT_INVITE)
        let criteriaValid = if shouldUseRelaxedValidation {
            lengthValid || allowedCharactersRuleValid
        } else {
            lengthValid && allowedCharactersRuleValid
        }
        let canContinue = criteriaValid && isAffordable
        let costRule: UsernameValidationRuleResult = uiState.hasInvite ? .hidden : (hasEnoughBalance ? .valid : .invalid)
        
        uiState = CreateUsernameUIState(
            lengthRule: lengthValid ? .valid : .invalid,
            allowedCharactersRule: allowedCharactersRuleValid ? .valid : .invalid,
            costRule: costRule,
            usernameBlockedRule: canContinue && isContested ? .loading : .hidden,
            contestedAllowed: uiState.contestedAllowed,
            hasInvite: uiState.hasInvite,
            isInvitationMixed: uiState.isInvitationMixed,
            isInvitationForContested: uiState.isInvitationForContested,
            requiredDash: requiredCost,
            canContinue: false
        )
        
        if canContinue {
            if isContested {
                Task {
                    await checkIfBlocked(username: username)
                }
            } else {
                uiState.canContinue = true
            }
        }
    }
    
    private func checkIfBlocked(username: String) async {
        // TODO: MOCK_DASHPAY remove
        let oneSecond = TimeInterval(1_000_000_000)
        let delay = UInt64(oneSecond * 2)
        try! await Task.sleep(nanoseconds: delay)
        
        if self.username == username {
            uiState.usernameBlockedRule = .warning
            uiState.canContinue = true
        }
    }
    
    private func observeBalance() {
        checkBalance()
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.validateUsername(username: self.username)
                self.checkBalance()
            }
            .store(in: &cancellableBag)
    }
    
    private func checkBalance() {
        let balance = DWEnvironment.sharedInstance().currentAccount.balance
        self.balance = balance.dashAmount.formattedDashAmountWithoutCurrencySymbol
        hasMinimumRequiredBalance = balance >= DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        hasRecommendedBalance = balance >= DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME
    }

    private func isUsernameContestable(username: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: "^[a-zA-Z01-]{3,19}$")
        let range = NSRange(location: 0, length: username.utf16.count)
        
        return regex.firstMatch(in: username, options: [], range: range) != nil
    }
    
    private func isLengthValid(username: String) -> Bool {
        let shouldUseRelaxedMinLength = (uiState.hasInvite && !uiState.isInvitationForContested) || (!uiState.hasInvite && !ALLOW_CONTESTED_USERNAMES_WITHOUT_INVITE)
        let minLength = shouldUseRelaxedMinLength ? DW_MIN_USERNAME_NONCONTESTED_LENGTH : DW_MIN_USERNAME_LENGTH

        return username.count >= minLength && username.count <= DW_MAX_USERNAME_LENGTH
    }

    private func allowedCharactersRuleValid(username: String) -> Bool {
        let hasIllegalCharacters = username.rangeOfCharacter(from: illegalChars) != nil
        let containsDigits = username.rangeOfCharacter(from: .decimalDigits) != nil
        let startsOrEndsWithHyphen = username.first == "-" || username.last == "-"

        let shouldUseRelaxedCharacterRules = (uiState.hasInvite && !uiState.isInvitationForContested) || (!uiState.hasInvite && !ALLOW_CONTESTED_USERNAMES_WITHOUT_INVITE)
        if shouldUseRelaxedCharacterRules {
            return !hasIllegalCharacters && containsDigits && !startsOrEndsWithHyphen
        }

        return !hasIllegalCharacters && !startsOrEndsWithHyphen
    }
}
