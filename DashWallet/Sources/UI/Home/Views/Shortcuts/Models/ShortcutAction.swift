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
    case payWithNFC
    case localCurrency
    case importPrivateKey
    case switchToTestnet
    case switchToMainnet
    case reportAnIssue
    case createUsername
    case receive
    case explore
    case spend
    case send
    case atm
    case sendToContact
    case crowdNode
    case coinbase
    case uphold
    case topper
    case dashDEX
}

extension ShortcutActionType {
    /// The 13 features available for shortcut bar customization
    static var customizableActions: [ShortcutActionType] {
        var actions: [ShortcutActionType] = [
            .buySellDash, .explore, .spend, .atm, .receive,
            .send, .scanToPay, .payToAddress,
            .coinbase, .uphold, .topper, .dashDEX
        ]
        let state = CrowdNode.shared.signUpState
        if state == .finished || state == .linkedOnline {
            actions.append(.crowdNode)
        }
        return actions
    }

    var iconName: String {
        switch self {

        case .secureWallet:
            return "shortcut-bar-backup"
        case .scanToPay:
            return "shortcut-bar-scan-qr"
        case .payToAddress:
            return "shortcut-bar-send-address"
        case .buySellDash:
            return "shortcut-bar-buy-sell"
        case .payWithNFC:
            return "shortcut_payWithNFC"
        case .localCurrency:
            return "shortcut_localCurrency"
        case .importPrivateKey:
            return "shortcut_importPrivateKey"
        case .switchToTestnet, .switchToMainnet:
            return "shortcut_switchNetwork"
        case .reportAnIssue:
            return "shortcut_reportAnIssue"
        case .createUsername:
            fatalError("Image not found for shortcut type: \(self)")
        case .receive:
            return "shortcut-bar-receive"
        case .explore:
            return "shortcut-bar-explore"
        case .spend:
            return "shortcut-bar-spend"
        case .send:
            return "shortcut-bar-send"
        case .atm:
            return "shortcut-bar-atm"
        case .sendToContact:
            return "shortcut-bar-send-contact"
        case .crowdNode:
            return "shortcut-bar-crowdnode"
        case .coinbase:
            return "shortcut-bar-coinbase"
        case .uphold:
            return "shortcut-bar-uphold"
        case .topper:
            return "shortcut-bar-topper"
        case .dashDEX:
            return "shortcut-dash-dex"
        }
    }

    var title: String {
        switch self {
        case .secureWallet:
            return NSLocalizedString("Backup",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .scanToPay:
            return NSLocalizedString("Scan QR",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .payToAddress:
            return NSLocalizedString("Send to Address",
                                     comment: "Translate it as short as possible! (24 symbols max)")
        case .buySellDash:
            return NSLocalizedString("Buy & Sell",
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
        case .spend:
            return NSLocalizedString("Spend", comment: "Translate it as short as possible! (24 symbols max)")
        case .send:
            return NSLocalizedString("Send", comment: "Translate it as short as possible! (24 symbols max)")
        case .atm:
            return NSLocalizedString("ATM", comment: "Translate it as short as possible! (24 symbols max)")
        case .sendToContact:
            return NSLocalizedString("Send to Contact", comment: "Translate it as short as possible! (24 symbols max)")
        case .crowdNode:
            return NSLocalizedString("CrowdNode", comment: "Translate it as short as possible! (24 symbols max)")
        case .coinbase:
            return NSLocalizedString("Coinbase", comment: "Translate it as short as possible! (24 symbols max)")
        case .uphold:
            return NSLocalizedString("Uphold", comment: "Translate it as short as possible! (24 symbols max)")
        case .topper:
            return NSLocalizedString("Topper", comment: "Translate it as short as possible! (24 symbols max)")
        case .dashDEX:
            return NSLocalizedString("Dash DEX", comment: "Translate it as short as possible! (24 symbols max)")
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
        guard let image = UIImage(named: type.iconName) else {
            fatalError("Image not found for shortcut type: \(self)")
        }
        return image
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
