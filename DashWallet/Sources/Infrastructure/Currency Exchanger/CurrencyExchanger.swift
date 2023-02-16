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
    static var localCurrencyDashPrice: NSDecimalNumber? {
        do {
            return try wrapped.rate(for: App.fiatCurrency) as NSDecimalNumber
        } catch {
            return nil
        }
    }

    @objc
    static var prices: [DSCurrencyPriceObject] {
        wrapped.currencies.compactMap { .init(code: $0.code, name: $0.name, price: $0.price as NSNumber) }
    }

    @objc
    static var localFormat: NumberFormatter {
        NumberFormatter.fiatFormatter
    }

    @objc
    static func startExchangeRateFetching() {
        wrapped.startExchangeRateFetching()
    }

    @objc
    static func localCurrencyStringForDashAmount(_ amount: UInt64) -> String {
        wrapped.fiatAmountString(for: amount.dashAmount)
    }

    @objc
    static func localCurrencyNumberForDashAmount(_ amount: UInt64) -> NSNumber? {
        if amount == 0 {
            return .init(integerLiteral: 0)
        }

        guard let local = localCurrencyDashPrice else {
            return nil
        }

        var n = local
            .multiplying(by: NSDecimalNumber(value: llabs(Int64(amount))))
            .dividing(by: NSDecimalNumber(value: DUFFS))
        let min = NSDecimalNumber(value: 1)
            .multiplying(byPowerOf10: -Int16(localFormat.maximumFractionDigits))

        // if the amount is too small to be represented in local currency (but is != 0) then return a string like "$0.01"
        if n.compare(min) == .orderedAscending {
            n = min
        }

        if amount < 0 {
            n = n.multiplying(by: NSDecimalNumber(value: -1))
        }

        return n
    }

    @objc(stringForDashAmount:)
    static func string(for dashAmount: UInt64) -> String {
        dashAmount.formattedDashAmount
    }

    @objc(fiatCurrencyString:forDashAmount:)
    static func fiatCurrencyString(_ currency: String, dashAmount: UInt64) -> String {
        wrapped.fiatAmountString(in: currency, for: dashAmount.dashAmount)
    }

    @objc(amountForLocalCurrency:)
    static func amount(for fiatAmount: Decimal) -> UInt64 {
        do {
            return try wrapped.convertToDash(amount: fiatAmount, currency: App.fiatCurrency).plainDashAmount
        } catch {
            return 0
        }
    }

    @objc
    static var localCurrencyCode: String {
        App.fiatCurrency
    }
}

// MARK: - CurrencyExchanger

public final class CurrencyExchanger {

    /// All available currencies
    ///
    /// - Returns: Array of `DSCurrencyPriceObject`
    ///
    ///
    var currencies: [RateObject] = []

    private let dataProvider: RatesProvider
    private var pricesByCode: [String: RateObject]!
    private var plainPricesByCode: [String: Decimal]!

    init(dataProvider: RatesProvider) {
        self.dataProvider = dataProvider
        configure(dataProvider: dataProvider)
    }

    public func hasRate(for currency: String) -> Bool {
        guard !currencies.isEmpty else { return false }
        guard plainPricesByCode[currency] != nil else { return false }

        return true
    }

    public func rate(for currency: String) throws -> Decimal {
        guard !currencies.isEmpty else { throw CurrencyExchanger.Error.ratesAreFetching }
        guard let rate = plainPricesByCode[currency] else { throw CurrencyExchanger.Error.ratesNotAvailable }

        return rate
    }

    public func convertDash(amount: Decimal, to currency: String) throws -> Decimal {
        if amount.isZero { return 0 }

        let rate = try rate(for: currency)
        let result = rate*amount

        let formatter = NumberFormatter.fiatFormatter(currencyCode: currency)
        let min: Decimal = 1/pow(10, formatter.maximumFractionDigits)

        guard result > min else {
            return min
        }

        return result
    }

    public func convertToDash(amount: Decimal, currency: String) throws -> Decimal {
        if amount.isZero { return 0 }

        let rate = try rate(for: currency)
        return amount/rate
    }

    public func convert(to currency: String, amount: Decimal, amountCurrency: String) throws -> Decimal {
        if amount.isZero { return 0 }

        if amountCurrency == kDashCurrency {
            let rate = try rate(for: currency)
            return amount/rate
        }

        let dashAmount = try convertToDash(amount: amount, currency: amountCurrency)
        let result = try convertDash(amount: dashAmount, to: currency)
        return result
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

            var pricesByCode: [String: RateObject] = [:]
            var plainPricesByCode: [String: Decimal] = [:]

            for rate in prices {
                pricesByCode[rate.code] = rate
                plainPricesByCode[rate.code] = rate.price
            }

            var array = prices.sorted(by: { $0.code < $1.code })

            let euroObj = pricesByCode["EUR"]
            let usdObj = pricesByCode["USD"]

            array.removeAll(where: { $0 == euroObj || $0 == usdObj })

            if let item = usdObj {
                array.insert(item, at: 0)
            }

            if let item = euroObj {
                array.insert(item, at: 0)
            }

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

// MARK: Helper methods

extension CurrencyExchanger {
    func fiatAmountString(in currency: String, for dashAmount: Decimal) -> String {
        do {
            let amount = try convertDash(amount: dashAmount, to: currency)
            return amount.formattedFiatAmount
        } catch CurrencyExchanger.Error.ratesAreFetching {
            return NSLocalizedString("Syncing...", comment: "Balance")
        } catch CurrencyExchanger.Error.ratesNotAvailable {
            return NSLocalizedString("Syncing...", comment: "Balance")
        } catch {
            return NSLocalizedString("Invalid amount", comment: "Balance")
        }
    }

    func fiatAmountString(for dashAmount: Decimal) -> String {
        fiatAmountString(in: App.fiatCurrency, for: dashAmount)
    }
}
