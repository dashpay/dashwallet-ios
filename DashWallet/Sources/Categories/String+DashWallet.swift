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

private let kCurrencySymbol = "¤"
private var kDashSymbolAssetName = "icon_dash_currency"

//MARK: Formatted Amount

extension String {
    func dashSymbolAttributedString(with tintColor: UIColor) -> NSAttributedString {
        let image = UIImage(named: kDashSymbolAssetName)!.withTintColor(tintColor)
        
        let attachment = DashTextAttachment(image: image, verticalOffset: -1)
        
        return NSAttributedString(attachment: attachment)
    }
    
    func attributedAmountStringWithDashSymbol(tintColor: UIColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: self.trimmingCharacters(in: .whitespacesAndNewlines))
        
        let dashSymbolAttributedString = dashSymbolAttributedString(with: tintColor)
        if let range = attributedString.string.range(of: DASH) {
            attributedString.replaceCharacters(in: NSRange(range, in: attributedString.string), with: dashSymbolAttributedString)
        }else{
            attributedString.insert(.init(string: " "), at: 0)
            attributedString.insert(dashSymbolAttributedString, at: 0)
            attributedString.addAttribute(.foregroundColor, value: tintColor, range: .init(location: 0, length: attributedString.length))
        }
        
        return attributedString
    }
    
    /**
     Extract currency symbol from string formatted by number formatter
     
     @discussion By default, `NSNumberFormatter` uses `[NSLocale currentLocale]` to determine `currencySymbol`.
     When we manually set `currencyCode`, `currencySymbol` is no longer valid.
     For instance, if user has *_RU locale: `numberFormatter.currencySymbol` is RUB but formatted string is "1.23 US$",
     because he selected US Dollars as local price. So we have to manually parse the correct currency symbol.
     */
    func extractCurrencySymbol(using numberFormatter: NumberFormatter) -> String? {
        let format: String = numberFormatter.positiveFormat
        
        guard let currencySymbolRange = format.range(of: kCurrencySymbol) else {
            return nil
        }
        
        let isCurrencySymbolAtTheBeginning = currencySymbolRange.lowerBound == format.startIndex
        let isCurrencySymbolAtTheEnd = currencySymbolRange.upperBound == format.endIndex
        
        if !isCurrencySymbolAtTheBeginning && !isCurrencySymbolAtTheEnd {
            // special case to deal with RTL languages
            if format.hasPrefix("\u{0000200e}") || format.hasPrefix("\u{0000200f}") {
                return numberFormatter.currencySymbol
            }
        }
        
        var charSet: CharacterSet = .decimalDigits
        charSet.formUnion(.whitespaces)
        
        let separatedString = self.components(separatedBy: charSet)
        
        if isCurrencySymbolAtTheBeginning {
            return separatedString.first
        }else{
            return separatedString.last
        }
    }
}
