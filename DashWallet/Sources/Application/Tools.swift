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

private var _dashFormatter: NumberFormatter = {
    let maximumFractionDigits = 8

    var dashFormat = NumberFormatter.cryptoFormatter(currencyCode: DASH, exponent: maximumFractionDigits)
    dashFormat.maximum = (Decimal(MAX_MONEY)/pow(10, maximumFractionDigits)) as NSNumber
    return dashFormat
}()

extension NumberFormatter {
    static var dashFormatter: NumberFormatter {
        _dashFormatter
    }

    static func cryptoFormatter(currencyCode: String, exponent: Int) -> NumberFormatter {
        var formatter = NumberFormatter()
        formatter.isLenient = true
        formatter.numberStyle = .currency
        formatter.generatesDecimalNumbers = true
        if let range = formatter.positiveFormat.range(of: "#") {
            formatter.negativeFormat = formatter.positiveFormat.replacingCharacters(in: range, with: "-#")
        }

        formatter.currencyCode = currencyCode
        formatter.currencySymbol = currencyCode
        formatter.maximumFractionDigits = exponent
        formatter.minimumFractionDigits = 0

        return formatter
    }
}

