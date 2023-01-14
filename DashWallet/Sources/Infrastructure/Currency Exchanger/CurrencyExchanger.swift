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

// MARK: - CurrencyExchangerObjcWrapper

@objc
class CurrencyExchangerObjcWrapper: NSObject {
    private static var wrapped = CurrencyExchanger.shared

    @objc
    static func startExchangeRateFetching() {
        wrapped.startExchangeRateFetching()
    }
}

// MARK: - CurrencyExchanger

public final class CurrencyExchanger {

    /// All available currencies
    ///
    /// - Returns: Array of `DSCurrencyPriceObject`
    ///
    ///
    var currencies: [DSCurrencyPriceObject] = []

    private let dataProvider: RatesProvider

    init(dataProvider: RatesProvider) {
        self.dataProvider = dataProvider
        configure(dataProvider: dataProvider)
    }

    public func rate(baseCurrency: String, to currency: String) -> Decimal {
        0
    }

    public func amount(in currency: String, for input: UInt64, inputCurrency: String) -> Decimal {
        0
    }

    public func amount(in currency: String, for input: Decimal, inputCurrency: String) -> Decimal {
        0
    }

    public func convert(amount: Decimal, inputCurrency: String, outputCurrency: String) -> Decimal {
        0
    }

    static let shared = CurrencyExchanger(dataProvider: RatesProviderFactory.base)
}

extension CurrencyExchanger {
    public func startExchangeRateFetching() {
        dataProvider.startExchangeRateFetching()
    }

    internal func configure(dataProvider: RatesProvider) {
        dataProvider.updateHandler = { [weak self] prices in
            guard let self else { return }

            self.currencies = prices
        }
    }
}

// MARK: CurrencyExchanger.Error

extension CurrencyExchanger {
    enum Error {
        case ratesNotAvailable
        case invalidAmount
    }
}
