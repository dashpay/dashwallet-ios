//
//  Created by tkhp
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

final class CNCreateAccountTxDetailsModel {
    var title: String { NSLocalizedString("CrowdNode · Account", comment: "") }
    var iconName = "tx.item.cn.icon"
    
    var fiatAmount: String {
        (try? CurrencyExchanger.shared.convertDash(amount: dashAmount.dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
            NSLocalizedString("Updating Price", comment: "Updating Price")
    }

    func dashAmountString(with font: UIFont) -> NSAttributedString {
        return NSAttributedString("")
    }

    var transactions: [Transaction]
    private(set) var dashAmount: UInt64
    private(set) var netAmount: Int64

    init(transactions: [Transaction]) {
        self.transactions = transactions

        netAmount = transactions.reduce(0) { partialResult, tx in
            var r = partialResult
            let direction = tx.direction

            switch direction {
            case .sent:
                r -= Int64(tx.dashAmount)
            case .received:
                r += Int64(tx.dashAmount)
            default:
                break
            }

            return r
        }

        dashAmount = UInt64(abs(netAmount))
    }
}

