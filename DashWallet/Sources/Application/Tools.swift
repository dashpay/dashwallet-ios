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

private var _decimalFormatter: NumberFormatter!
private var _fiatFormatter: NumberFormatter!
private var _dashFormatter: NumberFormatter = {
    let maximumFractionDigits = 8

    var dashFormat = NumberFormatter.cryptoFormatter(currencyCode: DASH, exponent: maximumFractionDigits)
    dashFormat.locale = Locale.current
    dashFormat.maximum = (Decimal(MAX_MONEY)/pow(10, maximumFractionDigits)) as NSNumber

    return dashFormat
}()

extension NumberFormatter {
    static var decimalFormatter: NumberFormatter {
        guard let formatter = _decimalFormatter else {
            let formatter = NumberFormatter()
            formatter.isLenient = true
            formatter.numberStyle = .none
            formatter.generatesDecimalNumbers = true
            formatter.locale = Locale.current
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 20
            _decimalFormatter = formatter
            return formatter
        }

        return formatter
    }

    static var fiatFormatter: NumberFormatter {
        if let fiatFormatter = _fiatFormatter, fiatFormatter.currencyCode == App.fiatCurrency {
            return fiatFormatter
        }

        let formatter = fiatFormatter(currencyCode: App.fiatCurrency)
        formatter.locale = Locale.current
        _fiatFormatter = formatter
        return formatter
    }

    static var dashFormatter: NumberFormatter {
        _dashFormatter
    }

    static func cryptoFormatter(currencyCode: String, exponent: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.isLenient = true
        formatter.numberStyle = .currency
        formatter.generatesDecimalNumbers = true
        if let range = formatter.positiveFormat.range(of: "#") {
            formatter.negativeFormat = formatter.positiveFormat.replacingCharacters(in: range, with: "-#")
        }

        formatter.currencyCode = currencyCode

        if currencyCode == "DASH" {
            formatter.currencySymbol = currencyCode
        }

        formatter.maximumFractionDigits = exponent
        formatter.minimumFractionDigits = 0

        return formatter
    }

    static func fiatFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.isLenient = true
        formatter.numberStyle = .currency
        formatter.generatesDecimalNumbers = true
        formatter.currencyCode = currencyCode
        return formatter
    }
}

