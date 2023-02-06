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

@objc
extension DSTransaction {
    var date: Date {
        guard timestamp > 1 else {
            let chain = DWEnvironment.sharedInstance().currentChain
            let now = chain.timestamp(forBlockHeight: UInt32(TX_UNCONFIRMED))
            return Date(timeIntervalSince1970: now)
        }

        let txDate = Date(timeIntervalSince1970: timestamp)
        return txDate;
    }
}

// MARK: UI
@objc
extension DSTransaction {
    var formattedShortTxDate: String {
        DWDateFormatter.sharedInstance().shortString(from: date)
    }

    var formattedLongTxDate: String {
        DWDateFormatter.sharedInstance().longString(from: date)
    }

    var formattedISO8601TxDate: String {
        DWDateFormatter.sharedInstance().iso8601String(from: date)
    }


}

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

    var icon: UIImage {
        switch self {
        case .moved:
            return UIImage(named: "tx.item.internal.icon")!
        case .sent:
            return systemImage("arrow.up.circle.fill")
        case .received:
            return systemImage("arrow.down.circle.fill")
        case .notAccountFunds:
            return systemImage("arrow.down.circle.fill")
        @unknown default:
            fatalError()
        }
    }


    private func systemImage(_ name: String) -> UIImage {
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 50, weight: .regular, scale: .unspecified)
        return UIImage(systemName: "arrow.down.circle.fill", withConfiguration: iconConfig)!
    }

    var directionSymbol: String {
        switch self {
        case .moved:
            return "⟲"
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
        case .received:
            return .dw_dashBlue()
        case .notAccountFunds:
            return .dw_dashBlue()
        }
    }
}
