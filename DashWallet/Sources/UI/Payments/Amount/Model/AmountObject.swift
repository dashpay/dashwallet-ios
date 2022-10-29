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

struct AmountObject {
    let amountInternalRepresentation: String
    let plainAmount: Int64
    let amountType: AmountType
    
    let mainFormatted: String
    let supplementaryFormatted: String
    
    let localFormatter: NumberFormatter
    let fiatCurrencyCode: String

    init(dashAmountString: String, fiatCurrencyCode: String, localFormatter: NumberFormatter) {
        self.amountType = .main
        self.amountInternalRepresentation = dashAmountString
        self.fiatCurrencyCode = fiatCurrencyCode
        self.localFormatter = localFormatter
        
        var dashAmountString = dashAmountString
        
        if dashAmountString.isEmpty {
            dashAmountString = "0"
        }
        
        let dashNumber = Decimal(string: dashAmountString, locale: .current)!
        let duffsNumber = Decimal(DUFFS)
        let plainAmount = dashNumber * duffsNumber
        
        self.plainAmount = NSDecimalNumber(decimal: plainAmount).int64Value
        
        mainFormatted = NumberFormatter.dashFormatter.inputString(from: dashNumber as NSNumber, and: dashAmountString) ?? NSLocalizedString("Invalid Input", comment: "Invalid Amount Input")
        
        let priceManager = DSPriceManager.sharedInstance()
        
        if let localNumber = priceManager.fiatCurrencyNumber(fiatCurrencyCode, forDashAmount: self.plainAmount),
           let str = localFormatter.string(from: localNumber) {
            supplementaryFormatted = str
        }else{
            supplementaryFormatted = NSLocalizedString("Updating Price", comment: "Updating Price")
        }
    }
    
    init?(localAmountString: String, fiatCurrencyCode: String, localFormatter: NumberFormatter) {
        self.amountType = .supplementary
        self.amountInternalRepresentation = localAmountString
        self.fiatCurrencyCode = fiatCurrencyCode
        self.localFormatter = localFormatter
        
        var localAmountString = localAmountString
        
        if localAmountString.isEmpty {
            localAmountString = "0"
        }
        
        let localNumber = Decimal(string: localAmountString, locale: .current)!
        let localCurrencyFormatted = localFormatter.inputString(from: localNumber as NSNumber, and: localAmountString)!
        
        //TODO: Refactor the way we calculate price for dash
        let priceManager = DSPriceManager.sharedInstance()
        let localPrice = priceManager.price(forCurrencyCode: fiatCurrencyCode)!.price
        let plainAmount = priceManager.amount(forLocalCurrencyString: localCurrencyFormatted, localFormatter: localFormatter, localPrice: localPrice)
        
        if plainAmount == 0 && localNumber.isEqual(to: .zero) {
            return nil
        }else{
            self.plainAmount = Int64(plainAmount)
            mainFormatted = priceManager.string(forDashAmount: self.plainAmount)!
            supplementaryFormatted = localCurrencyFormatted
        }
    }
}

extension AmountObject {
    func dashAmount(dashValidator: DWAmountInputValidator, localFormatter: NumberFormatter, currencyCode: String) -> AmountObject {
        if amountType == .main { return self }
        
        let priceManager = DSPriceManager.sharedInstance()
        
        let number = NumberFormatter.dashFormatter.number(from: mainFormatted)!
        let rawAmount = dashValidator.stringFromNumber(usingInternalFormatter: number)!
        
        return AmountObject(amountInternalRepresentation: rawAmount, plainAmount: plainAmount, amountType: .main, mainFormatted: mainFormatted, supplementaryFormatted: supplementaryFormatted, localFormatter: localFormatter, fiatCurrencyCode: currencyCode)
    }
    
    func localAmount(localValidator: DWAmountInputValidator, localFormatter: NumberFormatter, currencyCode: String) -> AmountObject {
        if amountType == .supplementary { return self }
        
        let priceManager = DSPriceManager.sharedInstance()
        
        let number = localFormatter.number(from: supplementaryFormatted)!
        let rawAmount = localValidator.stringFromNumber(usingInternalFormatter: number)!
        
        return AmountObject(amountInternalRepresentation: rawAmount, plainAmount: plainAmount, amountType: .main, mainFormatted: mainFormatted, supplementaryFormatted: supplementaryFormatted, localFormatter: localFormatter, fiatCurrencyCode: currencyCode)
    }
    
    init(amountInternalRepresentation: String, plainAmount: Int64, amountType: AmountType, mainFormatted: String, supplementaryFormatted: String, localFormatter: NumberFormatter, fiatCurrencyCode: String) {
        self.amountInternalRepresentation = amountInternalRepresentation
        self.plainAmount = plainAmount
        self.amountType = amountType
        self.mainFormatted = mainFormatted
        self.supplementaryFormatted = supplementaryFormatted
        self.localFormatter = localFormatter
        self.fiatCurrencyCode = fiatCurrencyCode
    }
}
