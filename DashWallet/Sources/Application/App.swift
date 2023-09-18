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



// MARK: - Constants
private let kFiatCurrencyCodeKey = "LOCAL_CURRENCY_CODE"

// MARK: - AppObjcWrapper

@objc(DWApp)
class AppObjcWrapper: NSObject {
    @objc
    static let fiatCurrencyDidChangeNotification = Notification.Name.fiatCurrencyDidChange

    @objc
    static var dashFormatter: NumberFormatter {
        NumberFormatter.dashFormatter
    }

    @objc static var localCurrencyCode: String {
        get {
            App.fiatCurrency
        }
        set {
            App.shared.fiatCurrency = newValue
        }
    }

    @objc
    class func cleanUp() {
        App.shared.cleanUp()
    }
}

// MARK: - App

final class App {
    private var _fiatCurrency: String!

    public var fiatCurrency: String {
        get {
            if let currency = _fiatCurrency {
                return currency
            }

            guard let currency = UserDefaults.standard.value(forKey: kFiatCurrencyCodeKey) as? String else {
                if #available(iOS 16, *) {
                    _fiatCurrency = Locale.current.currency?.identifier ?? kDefaultCurrencyCode

                    return _fiatCurrency
                } else {
                    _fiatCurrency = NSLocale.current.currencyCode ?? kDefaultCurrencyCode

                    return _fiatCurrency
                }
            }

            _fiatCurrency = currency

            return _fiatCurrency
        }
        set {
            _fiatCurrency = newValue

            UserDefaults.standard.set(newValue, forKey: kFiatCurrencyCodeKey)
            NotificationCenter.default.post(name: Notification.Name.fiatCurrencyDidChange, object: nil)
        }
    }

    static func initialize() { }

    static let shared = App()

    func cleanUp() {
        TxUserInfoDAOImpl.shared.deleteAll()
        AddressUserInfoDAOImpl.shared.deleteAll()
        Coinbase.shared.reset()
    }
}

extension App { }

extension App {
    static var fiatCurrency: String { shared.fiatCurrency }
}

// MARK: - Events
private let kFiatCurrencyDidChange = "FiatCurrencyDidChange"

extension Notification.Name {
    static let fiatCurrencyDidChange = Notification.Name(kFiatCurrencyDidChange)
}
