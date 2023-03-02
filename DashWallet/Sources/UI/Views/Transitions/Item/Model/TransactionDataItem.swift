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

// MARK: - TransactionDataItem

protocol TransactionDataItem {
    var outputReceiveAddresses: [String] { get }
    var inputSendAddresses: [String] { get }
    var specialInfoAddresses: [String: Int]? { get }
    var dashAmount: UInt64 { get }
    var direction: DSTransactionDirection { get }
    var fiatAmount: String { get }

    var stateTitle: String { get }
    var shortDateString: String { get }
}

extension TransactionDataItem {
    var formattedDashAmountWithDirectionalSymbol: String {
        guard dashAmount != UInt64.max else {
            return NSLocalizedString("Syncing...", comment: "Transaction/Amount")
        }

        let formatted = dashAmount.formattedDashAmount

        if formatted.isCurrencySymbolAtTheBeginning {
            return direction.directionSymbol + " " + dashAmount.formattedDashAmount
        } else {
            return direction.directionSymbol + dashAmount.formattedDashAmount
        }
    }

    func attributedDashAmount(with font: UIFont, color: UIColor = .dw_label()) -> NSAttributedString {
        guard dashAmount != UInt64.max else {
            return NSAttributedString(string: NSLocalizedString("Syncing...", comment: "Transaction/Amount"))
        }

        var formatted = formattedDashAmountWithDirectionalSymbol
        return formatted.attributedAmountStringWithDashSymbol(tintColor: color, dashSymbolColor: color, font: font)
    }
}
