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

struct CreateUsernameUIState {
    var lengthRule: UsernameValidationRuleResult
    var allowedCharactersRule: UsernameValidationRuleResult
    var costRule: UsernameValidationRuleResult
    var usernameBlockedRule: UsernameValidationRuleResult
    var requiredDash: UInt64
    var canContinue: Bool
    
    init(lengthRule: UsernameValidationRuleResult, allowedCharactersRule: UsernameValidationRuleResult, costRule: UsernameValidationRuleResult, usernameBlockedRule: UsernameValidationRuleResult, requiredDash: UInt64, canContinue: Bool) {
        self.lengthRule = lengthRule
        self.allowedCharactersRule = allowedCharactersRule
        self.costRule = costRule
        self.usernameBlockedRule = usernameBlockedRule
        self.requiredDash = requiredDash
        self.canContinue = canContinue
    }
    
    init() {
        self.lengthRule = .empty
        self.allowedCharactersRule = .empty
        self.costRule = .hidden
        self.usernameBlockedRule = .hidden
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
            // TODO: simulation of a request. Remove when not needed
            // dashPayModel.createUsername(username, invitation: invitationURL)
            
            let now = Date().timeIntervalSince1970
            let identityData = withUnsafeBytes(of: UUID().uuid) { Data($0) }
            let identity = (identityData as NSData).base58String()
            let usernameRequest = UsernameRequest(requestId: UUID().uuidString, username: username, createdAt: Int64(now), identity: "\(identity)\(identity)", link: link?.absoluteString, votes: 0, blockVotes: 0, isApproved: false)
            
            await dao.create(dto: usernameRequest)
            prefs.requestedUsernameId = usernameRequest.requestId
            prefs.requestedUsername = usernameRequest.username
            
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
                prefs.requestedUsername = nil
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
    
    private func validateUsername(username: String) {
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !username.isEmpty else {
            uiState = CreateUsernameUIState()
            return
        }
        
        let isContested = false // TODO
        let lengthValid = username.count >= DW_MIN_USERNAME_LENGTH && username.count <= DW_MAX_USERNAME_LENGTH
        let hasIllegalCharacters = username.rangeOfCharacter(from: illegalChars) != nil
        let startsOrEndsWithHyphen = username.first == "-" || username.last == "-"
        let requiredCost = isContested ? DWDP_MIN_BALANCE_FOR_CONTESTED_USERNAME : DWDP_MIN_BALANCE_TO_CREATE_USERNAME
        let balance = DWEnvironment.sharedInstance().currentWallet.balance
        let hasEnoughBalance = balance >= requiredCost
        let canContinue = lengthValid && !hasIllegalCharacters && !startsOrEndsWithHyphen && hasEnoughBalance
        
        uiState = CreateUsernameUIState(
            lengthRule: lengthValid ? .valid : .invalid,
            allowedCharactersRule: hasIllegalCharacters || startsOrEndsWithHyphen ? .invalid : .valid,
            costRule: hasEnoughBalance ? .valid : .invalid,
            usernameBlockedRule: canContinue ? .loading : .hidden,
            requiredDash: requiredCost,
            canContinue: false
        )
        
        if canContinue {
            Task {
                await checkIfBlocked(username: username)
            }
        }
    }
    
    private func checkIfBlocked(username: String) async {
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
}
