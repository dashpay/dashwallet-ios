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

private let NBSP = "\u{00A0}" // no-break space (utf-8)

@objc
extension NSAttributedString {
    @objc(dw_dashAttributedStringForAmount:tintColor:symbolSize:)
    static func dashAttributedString(for amount: UInt64,
                                     tintColor: UIColor,
                                     symbolSize: CGSize) -> NSAttributedString {
        let dashAmount = amount.formattedDashAmount
        let result = dashAmount.attributedStringForDashSymbol(withTintColor: tintColor,
                                                              dashSymbolSize: symbolSize)
        return result!
    }

    @objc(dw_dashAttributedStringForAmount:tintColor:font:)
    static func dashAttributedString(for amount: UInt64,
                                     tintColor: UIColor,
                                     font: UIFont) -> NSAttributedString {
        dashAttributedString(for: amount, tintColor: tintColor, dashSymbolColor: nil, font: font)
    }

    @objc(dw_dashAttributedStringForAmount:tintColor:dashSymbolColor:font:)
    static func dashAttributedString(for amount: UInt64,
                                     tintColor: UIColor,
                                     dashSymbolColor: UIColor?,
                                     font: UIFont) -> NSAttributedString {
        let string = amount.formattedDashAmount

        return dashAttributedString(for: string,
                                    tintColor: tintColor,
                                    dashSymbolColor: dashSymbolColor,
                                    font: font)
    }

    @objc(dw_dashAttributedStringForFormattedAmount:tintColor:font:)
    static func dashAttributedString(for formattedAmount: String,
                                     tintColor: UIColor,
                                     font: UIFont) -> NSAttributedString {
        dashAttributedString(for: formattedAmount, tintColor: tintColor, dashSymbolColor: tintColor, font: font)
    }

    @objc(dw_dashAttributedStringForFormattedAmount:tintColor:dashSymbolColor:font:)
    static func dashAttributedString(for formattedAmount: String,
                                     tintColor: UIColor,
                                     dashSymbolColor: UIColor?,
                                     font: UIFont) -> NSAttributedString {
        let dashSymbolAttributedString = dashSymbolAttributedString(for: font,
                                                                    tintColor: dashSymbolColor != nil ? dashSymbolColor! : tintColor)

        let attributedString = NSMutableAttributedString(string: formattedAmount)

        let range = (attributedString.string as NSString).range(of: DASH)
        let dashSymbolFound = range.location != NSNotFound
        if dashSymbolFound {
            attributedString.replaceCharacters(in: range, with: dashSymbolAttributedString)
        } else {
            attributedString.insert(NSAttributedString(string: NBSP), at: 0)
            attributedString.insert(dashSymbolAttributedString, at: 0)
        }

        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.addAttribute(NSAttributedString.Key.foregroundColor, value: tintColor, range: fullRange)
        attributedString.addAttribute(NSAttributedString.Key.font, value: font, range: fullRange)

        return attributedString.copy() as! NSAttributedString
    }

    @objc(dw_dashAddressAttributedString:withFont:showingLogo:)
    static func dashAddressAttributedString(_ address: String, with font: UIFont, showingLogo: Bool) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()

        if showingLogo {
            let scaleFactor: CGFloat = 1.5 // 24pt (image size) / 16pt (font size)
            let side = font.pointSize * scaleFactor
            let symbolSize = CGSize(width: side, height: side)
            let dashIcon = NSTextAttachment()
            let y: CGFloat = -3.335 * scaleFactor // -5pt / scaleFactor
            dashIcon.bounds = CGRect(x: 0, y: y, width: symbolSize.width, height: symbolSize.height)
            dashIcon.image = UIImage(named: "icon_tx_list_dash")
            let dashIconAttributedString = NSAttributedString(attachment: dashIcon)

            attributedString.insert(NSAttributedString(string: "\u{00A0}"), at: 0)
            attributedString.insert(dashIconAttributedString, at: 0)
        }

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let attributedAddress = NSAttributedString(string: address, attributes: attributes)
        attributedString.append(attributedAddress)

        return attributedString.copy() as! NSAttributedString
    }

    @objc(dw_dashAddressAttributedString:withFont:)
    static func dashAddressAttributedString(_ address: String, with font: UIFont) -> NSAttributedString {
        dashAddressAttributedString(address, with: font, showingLogo: false)
    }

    // Private function
    private static func dashSymbolAttributedString(for font: UIFont, tintColor: UIColor) -> NSAttributedString {
        let scaleFactor: CGFloat = 0.665
        let side = font.pointSize * scaleFactor
        let symbolSize = CGSize(width: side, height: side)
        let dashSymbol = NSTextAttachment()
        dashSymbol.bounds = CGRect(x: 0, y: 0, width: symbolSize.width, height: symbolSize.height)
        dashSymbol.image = UIImage(named: "icon_dash_currency")?.sd_tintedImage(with: tintColor)

        return NSAttributedString(attachment: dashSymbol)
    }
}
