//
//  Created by Codex
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

enum MayaAmountFormatter {
    static func dashRoundedDown(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 5, .down)
        return result
    }

    static func dashDisplayString(_ value: Decimal, locale: Locale = .current) -> String {
        decimalString(
            from: dashRoundedDown(value),
            maximumFractionDigits: 5,
            locale: locale,
            usesGroupingSeparator: false,
            roundingMode: .down
        )
    }

    static func coinDisplayString(_ value: Decimal, locale: Locale = .current, usesGroupingSeparator: Bool = false) -> String {
        decimalString(
            from: value,
            maximumFractionDigits: 5,
            locale: locale,
            usesGroupingSeparator: usesGroupingSeparator,
            roundingMode: .halfUp
        )
    }

    static func fiat(_ value: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private static func decimalString(
        from value: Decimal,
        maximumFractionDigits: Int,
        locale: Locale,
        usesGroupingSeparator: Bool,
        roundingMode: NumberFormatter.RoundingMode
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = usesGroupingSeparator
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = roundingMode
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
