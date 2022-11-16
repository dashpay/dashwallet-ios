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

extension NumberFormatter {
    func inputString(from number: NSNumber, and inputString: String, locale: Locale = Locale.current) -> String? {
        guard let formattedString = self.string(from: number) else {
            return nil
        }
        
        let numberFormatter = self
        
        assert(numberFormatter.numberStyle == .currency, "Invalid number formatter")
                guard let decimalSeparator = locale.decimalSeparator else { return "" }
        assert(numberFormatter.decimalSeparator == decimalSeparator, "Custom decimal separators are not supported")
        
        guard let inputSeparatorRange = inputString.range(of: decimalSeparator) else {
            return formattedString
        }
        
        var currencySymbol = formattedString.extractCurrencySymbol(using: numberFormatter)
        
        if currencySymbol == nil &&
            numberFormatter.currencySymbol.range(of: DASH) != nil {
            currencySymbol = numberFormatter.currencySymbol
        }
        
        guard let currencySymbol = currencySymbol else {
            return formattedString
        }
        
        guard let currencySymbolRange = formattedString.range(of: currencySymbol) else {
            assertionFailure("Invalid formatted string")
            return ""
        }
        
        
        let isCurrencySymbolAtTheBeginning = currencySymbolRange.lowerBound == formattedString.startIndex
        var currencySymbolNumberSeparator: String
        
        if isCurrencySymbolAtTheBeginning {
            currencySymbolNumberSeparator = String(formattedString[ currencySymbolRange.upperBound..<formattedString.index(after: currencySymbolRange.upperBound)])
        }else{
            currencySymbolNumberSeparator = String(formattedString[formattedString.index(before: currencySymbolRange.upperBound)..<currencySymbolRange.upperBound])
        }
        
        if currencySymbolNumberSeparator.rangeOfCharacter(from: .whitespaces) == nil {
            currencySymbolNumberSeparator = ""
        }
        
        var formattedStringWithoutCurrency = formattedString.replacingCharacters(in: currencySymbolRange, with: "").trimmingCharacters(in: .whitespaces)
        
        let inputFractionPartWithSeparator = inputString.suffix(from: inputSeparatorRange.lowerBound)
        
        var formattedSeparatorIndex: String.Index! = formattedStringWithoutCurrency.range(of: decimalSeparator)?.lowerBound
        
        if formattedSeparatorIndex == nil {
            formattedSeparatorIndex = formattedStringWithoutCurrency.endIndex
            formattedStringWithoutCurrency = formattedStringWithoutCurrency + decimalSeparator
        }
        
        let formattedFractionPartRange = formattedSeparatorIndex..<formattedStringWithoutCurrency.endIndex
        
        let formattedStringWithFractionInput = formattedStringWithoutCurrency.replacingCharacters(in: formattedFractionPartRange, with: inputFractionPartWithSeparator)
        
        let resut: String
        
        if isCurrencySymbolAtTheBeginning {
            resut = currencySymbol + currencySymbolNumberSeparator + formattedStringWithFractionInput
        }else{
            resut = formattedStringWithFractionInput + currencySymbolNumberSeparator + currencySymbol
        }
        
        return resut
    }
}
