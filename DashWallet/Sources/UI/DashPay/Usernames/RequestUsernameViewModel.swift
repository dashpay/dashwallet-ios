//  
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

@objc
public class RequestUsernameVMObjcWrapper: NSObject {
    @objc
    public class func getRootVC(with completionHandler: ((Bool) -> ())?) -> UIViewController {
        let vm = RequestUsernameViewModel.shared
        vm.completionHandler = completionHandler
        
        if vm.hasUsernameRequest {
            return RequestDetailsViewController.controller()
        } else if vm.shouldShowFirstTimeInfo {
            return WelcomeToDashPayViewController.controller()
        } else {
            return RequestUsernameViewController.controller()
        }
    }
}

class RequestUsernameViewModel {
    private var cancellableBag = Set<AnyCancellable>()
    private let dao: UsernameRequestsDAO = UsernameRequestsDAOImpl.shared
    private let prefs = VotingPrefs.shared
    
    var completionHandler: ((Bool) -> ())?
    var enteredUsername: String = ""
    @Published private(set) var hasEnoughBalance = false
    @Published private(set) var currentUsernameRequest: UsernameRequest? = nil
    
    var minimumRequiredBalance: String {
        return DWDP_MIN_BALANCE_TO_CREATE_USERNAME.formattedDashAmount
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
    
    var shouldShowFirstTimeInfo: Bool {
        get { !prefs.requestInfoShown }
        set { prefs.requestInfoShown = !newValue }
    }
    
    var hasUsernameRequest: Bool {
        prefs.requestedUsernameId != nil
    }
    
    var shouldRequestPayment: Bool {
        get { !prefs.alreadyPaid }
        set { prefs.alreadyPaid = !newValue }
    }
    
    public static let shared: RequestUsernameViewModel = .init()
    
    init() {
        observeBalance()
    }
    
    func hasRequests(for username: String) async -> Bool {
        return await dao.get(byUsername: username) != nil
    }
    
    func submitUsernameRequest(withProve link: URL?) async -> Bool {
        do {
            // TODO: simulation of a request. Remove when not needed
            
            let now = Date().timeIntervalSince1970
            let identityData = withUnsafeBytes(of: UUID().uuid) { Data($0) }
            let identity = (identityData as NSData).base58String()
            let usernameRequest = UsernameRequest(requestId: UUID().uuidString, username: enteredUsername, createdAt: Int64(now), identity: "\(identity)\(identity)", link: link?.absoluteString, votes: 0, isApproved: false)
            
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
                enteredUsername = currentUsernameRequest?.username ?? ""
            }
        }
    }
    
    func cancelRequest() {
        if let requestId = prefs.requestedUsernameId {
            Task {
                currentUsernameRequest = nil
                enteredUsername = ""
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
    
    func onFlowComplete(withResult: Bool) {
        completionHandler?(withResult)
    }
    
    private func observeBalance() {
        checkBalance()
        NotificationCenter.default.publisher(for: NSNotification.Name.DSWalletBalanceDidChange)
            .sink { [weak self] _ in self?.checkBalance() }
            .store(in: &cancellableBag)
    }
    
    private func checkBalance() {
        let balance = DWEnvironment.sharedInstance().currentAccount.balance
        hasEnoughBalance = balance >= DWDP_MIN_BALANCE_TO_CREATE_USERNAME
    }
}
