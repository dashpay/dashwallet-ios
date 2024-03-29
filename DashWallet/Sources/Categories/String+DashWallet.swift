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

// MARK: Formatted Amount
extension String {
    func localizedAmount(locale: Locale = .current) -> String {
        let separator = locale.decimalSeparator ?? "."

        guard contains(separator) else {
            let currentSeparator = locale.decimalSeparator == "." ? "," : "."
            return replacingOccurrences(of: currentSeparator, with: separator)
        }

        return self
    }

    // TODO: Better to generate images per font size
    func dashSymbolAttributedString(with tintColor: UIColor) -> NSAttributedString {
        let image = UIImage(named: kDashSymbolAssetName)!.withTintColor(tintColor)

        let attachment = DashTextAttachment(image: image, verticalOffset: -1)

        return NSAttributedString(attachment: attachment)
    }

    func attributedAmountStringWithDashSymbol(tintColor: UIColor, dashSymbolColor: UIColor? = nil, font: UIFont? = nil) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: trimmingCharacters(in: .whitespacesAndNewlines))

        let dashSymbolAttributedString = dashSymbolAttributedString(with: dashSymbolColor ?? tintColor)
        let dashSymbolRange = attributedString.string.nsRange(of: DASH)
        if dashSymbolRange.isValid {
            attributedString.replaceCharacters(in: dashSymbolRange, with: dashSymbolAttributedString)
        } else {
            attributedString.insert(.init(string: " "), at: 0)
            attributedString.insert(dashSymbolAttributedString, at: 0)
        }

        let amountLocation = dashSymbolRange.lowerBound == 0 ? 2 : 0
        let amountRange = NSRange(location: amountLocation,
                                  length: attributedString.string.count - 2)

        attributedString.addAttribute(.foregroundColor, value: tintColor, range: amountRange)

        if let font {
            attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributedString.string.count))
        }

        return attributedString
    }

    func attributedAmountForLocalCurrency(textColor: UIColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: self)

        let locale = Locale.current
        let decimalSeparator = locale.decimalSeparator!
        let insufficientFractionDigits = decimalSeparator + "00"
        let defaultAttributes = [NSAttributedString.Key.foregroundColor: textColor]

        attributedString.beginEditing()
        if let insufficientFractionDigitsRange = range(of: insufficientFractionDigits) {
            let range = NSRange(insufficientFractionDigitsRange, in: self)

            if range.location > 0 {
                let beforeFractionRange = NSMakeRange(0, range.location)
                attributedString.setAttributes(defaultAttributes, range: beforeFractionRange)
            }

            if range.length + range.location >= count {
                let fractionAttributes = [NSAttributedString.Key.foregroundColor: textColor.withAlphaComponent(0.5)]
                attributedString.setAttributes(fractionAttributes, range: range)
            }

            let afterFractionIndex = range.location + range.length
            if afterFractionIndex < count {
                let afterFractionRange = NSMakeRange(afterFractionIndex, count - afterFractionIndex)
                attributedString.setAttributes(defaultAttributes, range: afterFractionRange)
            }
        } else {
            attributedString.setAttributes(defaultAttributes, range: NSMakeRange(0, count))
        }

        attributedString.endEditing()

        return attributedString
    }


    var isCurrencySymbolAtTheBeginning: Bool {
        !(first?.isNumber ?? true)
    }

    /// Extract currency symbol from string formatted by number formatter
    ///
    /// @discussion By default, `NSNumberFormatter` uses `[NSLocale currentLocale]` to determine `currencySymbol`.
    /// When we manually set `currencyCode`, `currencySymbol` is no longer valid.
    /// For instance, if user has *_RU locale: `numberFormatter.currencySymbol` is RUB but formatted string is "1.23 US$",
    /// because he selected US Dollars as local price. So we have to manually parse the correct currency symbol.
    func extractCurrencySymbol(using numberFormatter: NumberFormatter) -> String? {
        let format: String = numberFormatter.positiveFormat

        guard let currencySymbolRange = format.range(of: kCurrencySymbol) else {
            return nil
        }

        let isCurrencySymbolAtTheBeginning = currencySymbolRange.lowerBound == format.startIndex

        // special case to deal with RTL languages
        if format.hasPrefix("\u{0000200e}") || format.hasPrefix("\u{0000200f}") {
            return numberFormatter.currencySymbol
        }

        var charSet: CharacterSet = .decimalDigits
        charSet.formUnion(.whitespaces)

        let separatedString = components(separatedBy: charSet).filter { !$0.isEmpty }

        if isCurrencySymbolAtTheBeginning {
            return separatedString.first
        } else {
            return separatedString.last
        }
    }

    /// Convert string to plain dash amount
    ///
    /// - Parameters:
    ///   - locale: Locale to use when converting string to decimal
    ///
    /// - Returns: Plain dash amount or nil
    ///
    /// - Note: This method expects string to be a number otherwise it returns nil
    func plainDashAmount(locale: Locale? = nil) -> UInt64? {
        guard let dashNumber = Decimal(string: self, locale: locale) else { return nil }

        let duffsNumber = Decimal(DUFFS)
        let plainAmount = dashNumber * duffsNumber
        let dashAmount = NSDecimalNumber(decimal: plainAmount)

        return dashAmount.uint64Value
    }

    func decimal(locale: Locale? = nil) -> Decimal? {
        Decimal(string: self, locale: locale)
    }

    func nsRange(of aString: String) -> NSRange {
        guard let range = range(of: aString) else {
            return NSMakeRange(NSNotFound, 0)
        }

        return NSRange(range, in: self)
    }
}

@objc
extension NSString {
    var wordsCount: UInt {
        var count: UInt = 0

        enumerateSubstrings(in: NSMakeRange(0, length), options: [.byWords]) { _, _, _, _ in
            count += 1
        }

        return count
    }
}

extension NSRange {
    var isValid: Bool {
        location != NSNotFound
    }
}

extension RangeReplaceableCollection where Self: StringProtocol {
    var digits: Self { filter(\.isWholeNumber) }
}
