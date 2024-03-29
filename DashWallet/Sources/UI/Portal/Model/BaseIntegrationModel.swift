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

import Foundation
import Combine

// MARK: - IntegrationItemType

enum IntegrationItemType: CaseIterable {
    case buyDash
    case sellDash
//    case convertCrypto // disabled per MO-103
    case transferDash
}

extension IntegrationItemType {
    var title: String {
        switch self {
        case .buyDash:
            return NSLocalizedString("Buy Dash", comment: "Integration Entry Point")
        case .sellDash:
            return NSLocalizedString("Sell Dash", comment: "Integration Entry Point")
//        case .convertCrypto:
//            return NSLocalizedString("Convert Crypto", comment: "Integration Entry Point")
        case .transferDash:
            return NSLocalizedString("Transfer Dash", comment: "Integration Entry Point")
        }
    }
    
    var icon: String {
        switch self {
        case .buyDash:
            return "integration.buy"
        case .sellDash:
            return "integration.sell"
//        case .convertCrypto:
//            return "integration.convert"
        case .transferDash:
            return "integration.transfer"
        }
    }
}

// MARK: - IntegrationItemType

protocol IntegrationEntryPointItem: ItemCellDataProvider {
    var type: IntegrationItemType { get }
}

// MARK: - IntegraionPortalModelState

enum IntegraionPortalModelState: Int {
    case loading
    case ready
    case failed
}

// MARK: - BaseIntegrationModel

class BaseIntegrationModel: BalanceViewDataSource {
    var cancellableBag = Set<AnyCancellable>()
    
    var mainAmountString: String { "" }
    var supplementaryAmountString: String { "" }
    var balanceTitle: String { "" }
    var signInTitle: String { "" }
    var signOutTitle: String { "" }
    var items: [IntegrationEntryPointItem] { [] }
    var shouldPopOnLogout: Bool { false }
    var authenticationUrl: URL? { nil }
    var logoutUrl: URL? { nil }
    @Published var isLoggedIn = false
    @Published var state: IntegraionPortalModelState = .ready
    
    let service: Service
    var userDidChange: (() -> ())?
    
    init(service: Service) {
        self.service = service
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellableBag)
    }
    
    func validate(operation type: IntegrationItemType) -> LocalizedError? {
        return nil
    }
    
    func handle(error: Error) { }
    
    func logIn(callbackUrl: URL?) { }
    
    func logOut() { }
    
    func refresh() { }
    
    func onFinish() { }
    
    func isValidCallbackUrl(url: URL) -> Bool {
        false
    }
}
