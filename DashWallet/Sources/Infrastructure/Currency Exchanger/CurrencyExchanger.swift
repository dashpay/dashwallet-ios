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
    private var pricesByCode: [String: DSCurrencyPriceObject]!
    private var plainPricesByCode: [String: NSNumber]!

    init(dataProvider: RatesProvider) {
        self.dataProvider = dataProvider
        configure(dataProvider: dataProvider)
    }

    public func rate(for currency: String) throws -> Decimal {
        guard !currencies.isEmpty else { throw CurrencyExchanger.Error.ratesAreFetching }
        guard let rate = plainPricesByCode[currency] else { throw CurrencyExchanger.Error.ratesNotAvailable }

        return rate.decimalValue
    }

    public func convertDash(amount: Decimal, to currency: String) throws -> Decimal {
        let rate = try rate(for: currency)
        let result = rate*amount

        let formatter = NumberFormatter.currencyFormatter(currencyCode: currency)
        let min: Decimal = 1/pow(10, formatter.maximumFractionDigits)

        guard result > min else {
            return min
        }

        return result
    }

    public func convertToDash(amount: Decimal, currency: String) throws -> Decimal {
        let rate = try rate(for: currency)
        return amount/rate
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

            var pricesByCode: [String: DSCurrencyPriceObject] = [:]
            var plainPricesByCode: [String: NSNumber] = [:]

            for rate in prices {
                pricesByCode[rate.code] = rate
                plainPricesByCode[rate.code] = rate.price
            }

            var array = prices.sorted(by: { $0.code < $1.code })

            let euroObj = pricesByCode["EUR"]!
            let usdObj = pricesByCode["USD"]!

            array.removeAll(where: { $0 == euroObj || $0 == usdObj })
            array.insert(euroObj, at: 0)
            array.insert(usdObj, at: 0)

            self.pricesByCode = pricesByCode
            self.plainPricesByCode = plainPricesByCode
            self.currencies = array
        }
    }
}

// MARK: CurrencyExchanger.Error

extension CurrencyExchanger {
    enum Error: Swift.Error {
        case ratesNotAvailable
        case ratesAreFetching
        case invalidAmount
    }
}
