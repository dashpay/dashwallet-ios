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
        
        if let balance = dashBalance, let fiat = fiatBalance {
            let dashStr = "\(balance) DASH"
            let fiatStr = " ≈ \(fiat)"
            let fullStr = "\(dashStr)\(fiatStr)"
            let string = NSMutableAttributedString(string: fullStr)
            string.addAttributes([NSAttributedString.Key.foregroundColor: UIColor.secondaryLabel], range: NSMakeRange(dashStr.count, fiatStr.count))
            string.addAttribute(.font, value: UIFont.dw_font(forTextStyle: .footnote), range: NSMakeRange(0, fullStr.count - 1))
            return string
        }
        
        return nil
    }
    
    var fiatBalance: String? {
        guard let balance = dashBalance else { return nil }
        
        let priceManger = DSPriceManager.sharedInstance()
        let dashAmount = DWAmountObject(dashAmountString: balance,
                                        localFormatter: priceManger.localFormat,
                                        currencyCode: priceManger.localCurrencyCode)
        
        return priceManger.localCurrencyString(forDashAmount: dashAmount.plainAmount)
    }
}

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
    
    var name: String { return service.title }
    var icon: String { return service.icon }
    
    var status: Status
    var service: Service

    var dashBalance: String?
    var usageCount: Int = 0
    
    var isInUse: Bool { return status == .syncing || status == .authorized }
    
    init(status: Status, service: Service, dashBalance: String? = nil) {
        self.status = status
        self.service = service
        self.dashBalance = dashBalance
        self.usageCount = service.usageCount
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
        //case .disconnected: return NSLocalizedString("Disconnected", comment: "Buy Sell Portal")
        case .syncing: return NSLocalizedString("Syncing", comment: "Buy Sell Portal")
        case .failed: return NSLocalizedString("Failed to sync", comment: "Buy Sell Portal")
        case .unknown, .idle: return ""
        }
        
    }
}

