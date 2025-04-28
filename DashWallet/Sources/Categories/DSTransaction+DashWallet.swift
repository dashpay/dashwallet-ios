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

extension DSTransaction {
    var type: Transaction.`Type` {
        if self is DSCoinbaseTransaction {
            return .reward;
        } else if self is DSProviderRegistrationTransaction {
            return .masternodeRegistration;
        } else if self is DSProviderUpdateRegistrarTransaction {
            return .masternodeUpdate;
        } else if self is DSProviderUpdateServiceTransaction {
            return .masternodeUpdate;
        } else if self is DSProviderUpdateRevocationTransaction {
            return .masternodeRevoke;
        } else if self is DSAssetLockTransaction {
            return .assetLock;
        } else if self is DSAssetUnlockTransaction {
            return .assetUnlock;
        }

        return .classic;
    }

    var outputReceiveAddresses: [String] {
        var outputReceiveAddresses: [String] = []

        let currentAccount = DWEnvironment.sharedInstance().currentAccount;
        let account = accounts.contains(where: { ($0 as! DSAccount) == currentAccount }) ? currentAccount : nil

        switch direction {
        case .moved, .sent, .received:
            outputReceiveAddresses = account?.externalAddresses(of: self) ?? []
        default:
            break
        }

        return outputReceiveAddresses
    }

    var specialInfoAddresses: [String: Int] {
        var specialInfoAddresses: [String: Int] = [:]

        switch direction {
        case .notAccountFunds:
            if let tx = self as? DSProviderRegistrationTransaction {
                specialInfoAddresses = [tx.ownerAddress!: 0, tx.operatorAddress: 1, tx.votingAddress: 2]
            } else if let tx = self as? DSProviderUpdateRegistrarTransaction {
                specialInfoAddresses = [tx.operatorAddress: 0, tx.votingAddress: 1]
            }
        default:
            break
        }

        return specialInfoAddresses
    }
}

// MARK: UI
@objc
extension DSTransaction {
    var formattedShortTxDate: String {
        DWDateFormatter.sharedInstance.dateOnly(from: date)
    }

    var formattedLongTxDate: String {
        DWDateFormatter.sharedInstance.longString(from: date)
    }

    var formattedISO8601TxDate: String {
        DWDateFormatter.sharedInstance.iso8601String(from: date)
    }
    
    var formattedShortTxTime: String {
        DWDateFormatter.sharedInstance.timeOnly(from: date)
    }

    var formattedDashAmountWithDirectionalSymbol: String {
        let formatted = dashAmount.formattedDashAmount

        if formatted.isCurrencySymbolAtTheBeginning {
            return direction.directionSymbol + " " + dashAmount.formattedDashAmount
        } else {
            return direction.directionSymbol + dashAmount.formattedDashAmount
        }
    }

    func attributedDashAmount(with font: UIFont, color: UIColor = .dw_label()) -> NSAttributedString {
        let formatted = formattedDashAmountWithDirectionalSymbol
        return formatted.attributedAmountStringWithDashSymbol(tintColor: color, dashSymbolColor: color, font: font)
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

    private func systemImage(_ name: String) -> UIImage {
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 50, weight: .regular, scale: .large)
        return UIImage(systemName: name, withConfiguration: iconConfig)!
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
