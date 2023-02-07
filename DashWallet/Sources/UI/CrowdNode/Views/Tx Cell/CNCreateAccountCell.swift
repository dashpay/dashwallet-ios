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

import UIKit

@objc
final class CNCreateAccountCell: UITableViewCell {
    @IBOutlet var txCountLabel: UILabel!
    @IBOutlet var amountLabel: UILabel!
    @IBOutlet var fiatAmountLabel: UILabel!
    @IBOutlet var txTitleLabel: UILabel!
    @IBOutlet var dateLabel: UILabel!

    func update(with transactions: [Transaction]) {
        txTitleLabel.text = NSLocalizedString("CrowdNode Account", comment: "Crowdnode")
        txCountLabel.text = String(format: NSLocalizedString("%d transaction(s)", comment: "#bc-ignore!"), transactions.count)
        dateLabel.text = transactions.last?.shortDateString

        let amount: Int64 = transactions.reduce(0) { partialResult, tx in
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

        let sign: String = amount < 0 ? "-" : "+"
        let dashAmount = UInt64(abs(amount))

        amountLabel.attributedText = (sign + abs(amount).formattedDashAmount)
            .attributedAmountStringWithDashSymbol(tintColor: .dw_label(), font: .dw_font(forTextStyle: .subheadline))

        fiatAmountLabel
            .text = (try? CurrencyExchanger.shared.convertDash(amount: dashAmount.dashAmount, to: App.fiatCurrency).formattedFiatAmount) ??
            NSLocalizedString("Updating Price", comment: "Updating Price")
    }
}
