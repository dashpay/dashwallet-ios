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
    var txHashHexString: String { get }
    var dashAmount: UInt64 { get }
    var signedDashAmount: Int64 { get }
    var direction: DSTransactionDirection { get }
    var fiatAmount: String { get }
    var iconName: String { get }
    var stateTitle: String { get }
    var shortDateString: String { get }
}

// MARK: - DSTransactionDirection UI formatting
// (Lives here with the rest of the tx-row formatting. The direction enum is
// still DashSync's — replacing it with an app-owned enum is a separate,
// repo-wide step tracked in the teardown plan.)

extension DSTransactionDirection {
    var title: String {
        switch self {
        case .sent:
            return NSLocalizedString("Amount Sent", comment: "");
        case .received:
            return NSLocalizedString("Amount received", comment: "");
        case .moved:
            return NSLocalizedString("Moved to Address", comment: "");
        case .notAccountFunds:
            return NSLocalizedString("Registered Masternode", comment: "");
        @unknown default:
            fatalError()
        }
    }

    var tintColor: UIColor {
        switch self {
        case .sent:
            return .dw_dashBlue()
        case .received:
            return .dw_green()
        case .moved:
            return .dw_orange()
        case .notAccountFunds:
            return .dw_label()
        @unknown default:
            return .dw_label()
        }
    }

    var iconName: String {
        switch self {
        case .moved:
            return "tx.item.internal.icon"
        case .sent:
            return "tx.item.sent.icon"
        case .received:
            return "tx.item.received.icon"
        case .notAccountFunds:
            return "tx.item.received.icon"
        @unknown default:
            fatalError()
        }
    }

    var icon: UIImage {
        return UIImage(named: iconName)!
    }

    var directionSymbol: String {
        switch self {
        case .received:
            return "+";
        case .sent:
            return "-";
        default:
            return "";
        }
    }

    var dashAmountTintColor: UIColor {
        switch self {
        case .moved:
            return .dw_quaternaryText()
        case .sent:
            return .dw_darkTitle()
        case .received, .notAccountFunds:
            return .dw_dashBlue()
        @unknown default:
            fatalError()
        }
    }
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

        let formatted = formattedDashAmountWithDirectionalSymbol
        return formatted.attributedAmountStringWithDashSymbol(tintColor: color, dashSymbolColor: color, font: font)
    }
}
