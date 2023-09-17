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

// MARK: - UpholdPortalModelState

enum UpholdPortalModelState: Int {
    case signedOut
    case loading
    case ready
    case failed
}

// MARK: - UpholdPortalModel

final class UpholdPortalModel {
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

    func logOut() {
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

// MARK: BalanceViewDataSource

extension UpholdPortalModel: BalanceViewDataSource {
    var mainAmountString: String {
        guard let dashCard else {
            return NSLocalizedString("Balance not available", comment: "Uphold entry point")
        }

        return dashCard.formattedDashAmount
    }

    var supplementaryAmountString: String {
        guard let dashCard else {
            return NSLocalizedString("Balance not available", comment: "Uphold entry point")
        }

        return dashCard.fiatBalanceFormatted(App.fiatCurrency)
    }
}
