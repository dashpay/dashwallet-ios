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

enum AmountType {
    case main
    case supplementary
}

struct AmountObject {
    let stringRepresentation: String
    let plainAmount: UInt64
    let amountType: AmountType
    
    private let fiatCurrencyCode: String
//    init(dashAmount: UInt64, fiatCurrencyCode: String) {
//        self.amountType = .main
//        self.plainAmount = dashAmount
//        self.fiatCurrencyCode = fiatCurrencyCode
//    }
    
    init(dashAmountString: String, fiatCurrencyCode: String) {
        self.amountType = .main
        self.stringRepresentation = dashAmountString
        self.fiatCurrencyCode = fiatCurrencyCode
        
        var dashAmountString = dashAmountString
        
        if dashAmountString.isEmpty {
            dashAmountString = "0"
        }
        
        let dashNumber = Decimal(string: dashAmountString, locale: Locale.current)!
        let duffsNumber = Decimal(DUFFS)
        let plainAmount = dashNumber * duffsNumber
        
        self.plainAmount = NSDecimalNumber(decimal: plainAmount).uint64Value
    }
}

class BaseAmountModel {
    
    var showMaxButton: Bool = true
    var activeAmountType: AmountType = .main
    var amount: UInt64 = 0
    
    func updateAmount(with replacementString: String, range: NSRange) {
        let d = Decimal(string: "0.1")
    }
}

extension BaseAmountModel: AmountViewDataSource {
    var dashAttributedString: NSAttributedString {
        return .init(string: "")
    }
    
    var localCurrencyAttributedString: NSAttributedString {
        return .init(string: "")
    }
    
    func supplementaryAmount(for text: String) -> String {
        guard let dashNumber = Decimal(string: text, locale: Locale.current) else { return "" }
        let duffsNumber = Decimal(DUFFS)
        let plainAmount = NSDecimalNumber(decimal: dashNumber * duffsNumber).uint64Value
        let currencyCode = DSPriceManager.sharedInstance().localCurrencyCode
        return DSPriceManager.sharedInstance().fiatCurrencyNumber(currencyCode, forDashAmount: Int64(plainAmount))?.stringValue ?? ""
    }
    
    func mainAmount(for text: String) -> String {
        guard let localNumber = Decimal(string: text, locale: Locale.current) else { return "" }
        
        let priceManager = DSPriceManager.sharedInstance()
        guard (priceManager.localCurrencyDashPrice != nil) else { return NSLocalizedString("Updating Price", comment: "Updating Price") }
//        let localCurrencyFormatted = [localFormatter stringFromNumber:localNumber];
//        NSNumber *localPrice = [priceManager priceForCurrencyCode:currencyCode].price;
//        uint64_t plainAmount = [priceManager amountForLocalCurrencyString:localCurrencyFormatted
//                                                           localFormatter:localFormatter
//                                                               localPrice:localPrice];
        let dashFormat = priceManager.dashFormat
        let plainAmount = priceManager.amount(forLocalCurrencyString: text)
        
        return NSDecimalNumber(value: plainAmount).multiplying(byPowerOf10: Int16(dashFormat.maximumFractionDigits)).stringValue
    }
    
}
