//
//  Created by PT
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

// MARK: IntegrationEntryPointItem

struct UpholdEntryPointItem: IntegrationEntryPointItem {
    let type: IntegrationItemType
    static let supportedCases = [.buyDash, .transferDash].map { UpholdEntryPointItem(type: $0) }
    
    var title: String { type.title }
    var icon: String { type.icon }

    var description: String {
        switch type {
        case .buyDash:
            return NSLocalizedString("Receive directly into Dash Wallet", comment: "Uphold Entry Point")
        case .transferDash:
            return NSLocalizedString("From Uphold to Dash Wallet", comment: "Uphold Entry Point")
        default:
            return ""
        }
    }
}

// MARK: - UpholdPortalModelState

enum UpholdPortalModelState: Int {
    case signedOut
    case loading
    case ready
    case failed
}

// MARK: - UpholdPortalModel

final class UpholdPortalModel: BaseIntegrationModel {
    private var cancellableBag = Set<AnyCancellable>()
    
    override var items: [IntegrationEntryPointItem] {
        UpholdEntryPointItem.supportedCases
    }
    
    private var state: UpholdPortalModelState = .loading {
        didSet {
            if oldValue != state {
                stateDidChangeHandler?(state)
            }
        }
    }

    private var dashCard: DWUpholdCardObject?
    private var fiatCards: [DWUpholdCardObject]?

    var stateDidChangeHandler: ((UpholdPortalModelState) -> Void)?
    
    
    override var mainAmountString: String {
        guard let dashCard else {
            return NSLocalizedString("Balance not available", comment: "Uphold entry point")
        }

        return dashCard.formattedDashAmount
    }

    override var supplementaryAmountString: String {
        guard let dashCard else {
            return NSLocalizedString("Balance not available", comment: "Uphold entry point")
        }

        return dashCard.fiatBalanceFormatted(App.fiatCurrency)
    }
    
    override var balanceTitle: String {
        NSLocalizedString("Dash balance on Uphold", comment: "Uphold Entry Point")
    }
    
    override var signOutTitle: String {
        NSLocalizedString("Disconnect Coinbase Account", comment: "Coinbase Entry Point")
    }
    
    
    init() {
        super.init(service: .uphold)
        
        NotificationCenter.default.publisher(for: NSNotification.Name.DWUpholdClientUserDidLogout)
            .sink { [weak self] _ in self?.userDidSignOut?() }
            .store(in: &cancellableBag)
    }

    func fetch() {
        state = .loading

        DWUpholdClient.sharedInstance().getCards { [weak self] dashCard, fiatCards in
            guard let self else { return }

            self.dashCard = dashCard
            self.fiatCards = fiatCards

            let success = dashCard != nil
            self.state = success ? .ready : .failed
        }
    }

    var buyDashURL: URL? {
        guard let dashCard else {
            return nil
        }

        return DWUpholdClient.sharedInstance().buyDashURL(forCard: dashCard)
    }

    override func signOut() {
        DWUpholdClient.sharedInstance().logOut()
    }

    func transactionURL(for transaction: DWUpholdTransactionObject) -> URL? {
        DWUpholdClient.sharedInstance().transactionURL(forTransaction: transaction)
    }

    func successMessageText(for transaction: DWUpholdTransactionObject) -> String {
        String(format: NSLocalizedString("Your transaction was sent and the amount should appear in your wallet in a few minutes.", comment: ""),
               NSLocalizedString("Transaction id", comment: ""), transaction.identifier)
    }
}
