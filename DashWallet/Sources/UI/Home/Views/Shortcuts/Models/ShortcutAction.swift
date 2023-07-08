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

// MARK: - ShortcutActionType

@objc(DWShortcutActionType)
enum ShortcutActionType: Int {
    case secureWallet = 1
    case scanToPay
    case payToAddress
    case buySellDash
    case syncNow
    case payWithNFC
    case localCurrency
    case importPrivateKey
    case switchToTestnet
    case switchToMainnet
    case reportAnIssue
    case createUsername
    case receive
    case explore
}

extension ShortcutActionType {
    var icon: UIImage {
        switch self {
        case .secureWallet:
            guard let image = UIImage(named: "shortcut_secureWalletNow") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .scanToPay:
            guard let image = UIImage(named: "shortcut_scanToPay") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .payToAddress:
            guard let image = UIImage(named: "shortcut_payToAddress") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .buySellDash:
            guard let image = UIImage(named: "shortcut_buySellDash") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .syncNow:
            guard let image = UIImage(named: "shortcut_syncNow") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .payWithNFC:
            guard let image = UIImage(named: "shortcut_payWithNFC") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .localCurrency:
            guard let image = UIImage(named: "shortcut_localCurrency") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .importPrivateKey:
            guard let image = UIImage(named: "shortcut_importPrivateKey") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .switchToTestnet, .switchToMainnet:
            guard let image = UIImage(named: "shortcut_switchNetwork") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .reportAnIssue:
            guard let image = UIImage(named: "shortcut_reportAnIssue") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .createUsername:
            fatalError("Image not found for shortcut type: \(self)")
        case .receive:
            guard let image = UIImage(named: "shortcut_receive") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        case .explore:
            guard let image = UIImage(named: "shortcut_explore") else {
                fatalError("Image not found for shortcut type: \(self)")
            }
            return image
        default:
            fatalError("Image not found for shortcut type: \(self)")
        }
    }

    var title: String {
        switch self {
        case .secureWallet:
            return NSLocalizedString("Backup",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .scanToPay:
            return NSLocalizedString("Scan",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .payToAddress:
            return NSLocalizedString("Send",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .buySellDash:
            return NSLocalizedString("Buy & Sell",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .syncNow:
            return NSLocalizedString("Sync Now",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .payWithNFC:
            return NSLocalizedString("Send with NFC",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .localCurrency:
            return NSLocalizedString("Local Currency",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .importPrivateKey:
            return NSLocalizedString("Import Private Key",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .switchToTestnet:
            return NSLocalizedString("Switch to Testnet",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .switchToMainnet:
            return NSLocalizedString("Switch to Mainnet",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .reportAnIssue:
            return NSLocalizedString("Report an Issue",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .createUsername:
            return NSLocalizedString("Join Evolution", comment: "Translate it as short as possible! (24 symbols max)")
        case .receive:
            return NSLocalizedString("Receive", comment: "Translate it as short as possible! (24 symbols max)")
        case .explore:
            return NSLocalizedString("Explore", comment: "Translate it as short as possible! (24 symbols max)")
        }
    }
}

// MARK: - ShortcutAction

@objc(DWShortcutAction)
class ShortcutAction: NSObject {
    @objc
    let type: ShortcutActionType

    @objc
    let enabled: Bool

    init(type: ShortcutActionType, enabled: Bool = true) {
        self.type = type
        self.enabled = enabled
    }

    @objc
    static func action(type: ShortcutActionType) -> ShortcutAction {
        ShortcutAction(type: type, enabled: true)
    }

    @objc
    static func action(type: ShortcutActionType, enabled: Bool) -> ShortcutAction {
        ShortcutAction(type: type, enabled: enabled)
    }
}

extension ShortcutAction {
    var title: String {
        type.title
    }

    var icon: UIImage {
        type.icon
    }

    var alpha: CGFloat {
        enabled ? 1 : 0.4
    }

    var showsGradientLayer: Bool {
        false
    }

    var textColor: UIColor {
        .dw_darkTitle()
    }
}
