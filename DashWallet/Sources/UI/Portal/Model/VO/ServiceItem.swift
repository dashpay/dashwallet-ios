//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

extension ServiceItem {
    var balanceValue: NSAttributedString? {
        if status == .syncing {
            return NSAttributedString(string: NSLocalizedString("Syncing...", comment: "Buy and Sell Dash"))
        }

        if let balance = dashBalanceFormatted, let fiat = fiatBalanceFormatted {
            let fiatStr = " ≈ \(fiat)"
            let fullStr = "\(balance)\(fiatStr)"
            let string = NSMutableAttributedString(string: fullStr)
            string.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.secondaryLabel],
                                 range: NSMakeRange(balance.count, fiatStr.count))
            string.addAttribute(.font, value: UIFont.dw_font(forTextStyle: .footnote), range: NSMakeRange(0, fullStr.count - 1))
            return string
        }

        return nil
    }
}

// MARK: - ServiceItem

class ServiceItem: Hashable {
    static func == (lhs: ServiceItem, rhs: ServiceItem) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    enum Status: Int {
        case unknown
        case idle
        case initializing
        case syncing
        case authorized
        case failed
    }

    var name: String { service.title }
    var subtitle: String { service.subtitle }
    var icon: String { service.icon }
    var showAdditionalInfo: Bool { service == .topper }

    var status: Status
    var service: Service

    var dashBalance: UInt64?
    var dashBalanceFormatted: String?
    var fiatBalanceFormatted: String?

    var usageCount = 0

    var isInUse: Bool { status == .syncing || status == .authorized || service == .topper }

    init(status: Status, service: Service, dashBalance: UInt64? = nil) {
        self.status = status
        self.service = service
        self.dashBalance = dashBalance
        usageCount = service.usageCount

        guard let dashBalance else { return }

        dashBalanceFormatted = dashBalance.formattedDashAmountWithoutCurrencySymbol
        fiatBalanceFormatted = Coinbase.shared.currencyExchanger.fiatAmountString(in: App.fiatCurrency, for: dashBalance.dashAmount)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(status.rawValue)
        hasher.combine(usageCount)
    }
}

extension ServiceItem.Status {
    var iconColor: UIColor {
        switch self {
        case .initializing: return .label
        case .authorized: return .systemGreen
        case .failed: return .systemRed
        case .unknown: return .label
        case .syncing: return .label
        case .idle: return .label
        }
    }

    var labelColor: UIColor {
        switch self {
        case .initializing: return .label
        case .authorized: return .label
        case .failed: return .systemRed
        case .unknown: return .label
        case .syncing: return .label
        case .idle: return .label
        }
    }

    var statusString: String {
        switch self {
        case .initializing: return NSLocalizedString("Initializing", comment: "Buy Sell Portal")
        case .authorized: return NSLocalizedString("Connected", comment: "Buy Sell Portal")
        // case .disconnected: return NSLocalizedString("Disconnected", comment: "Buy Sell Portal")
        case .syncing: return NSLocalizedString("Syncing", comment: "Buy Sell Portal")
        case .failed: return NSLocalizedString("Failed to sync", comment: "Buy Sell Portal")
        case .unknown, .idle: return ""
        }
    }
}

