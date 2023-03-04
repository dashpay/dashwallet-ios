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

private let kDefaultCurrencyCode = "USD"
private let kFiatCurrencyCodeKey = "LOCAL_CURRENCY_CODE"

extension App {
    var fiatCurrency: String {
        get {
            guard let currency = UserDefaults.standard.value(forKey: kFiatCurrencyCodeKey) as? String else {
                if #available(iOS 16, *) {
                    return Locale.current.currency?.identifier ?? kDefaultCurrencyCode
                } else {
                    return NSLocale.current.currencyCode ?? kDefaultCurrencyCode
                }
            }

            return currency
        }

        set {
            UserDefaults.standard.set(newValue, forKey: kFiatCurrencyCodeKey)
        }
    }
}

extension App {
    static var fiatCurrency: String { shared.fiatCurrency }
}
