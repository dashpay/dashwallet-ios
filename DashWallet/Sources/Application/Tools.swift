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

    var dashFormat = NumberFormatter()
    dashFormat.isLenient = true
    dashFormat.numberStyle = .currency
    dashFormat.generatesDecimalNumbers = true
    if let range = dashFormat.positiveFormat.range(of: "#") {
        dashFormat.negativeFormat = dashFormat.positiveFormat.replacingCharacters(in: range, with: "-#")
    }

    dashFormat.currencyCode = "DASH"
    dashFormat.currencySymbol = DASH
    dashFormat.maximumFractionDigits = maximumFractionDigits
    dashFormat.minimumFractionDigits = 0
    dashFormat.maximum = (Decimal(MAX_MONEY)/pow(10, maximumFractionDigits)) as NSNumber

    return dashFormat
}()

extension NumberFormatter {
    static var dashFormatter: NumberFormatter {
        _dashFormatter
    }
}

