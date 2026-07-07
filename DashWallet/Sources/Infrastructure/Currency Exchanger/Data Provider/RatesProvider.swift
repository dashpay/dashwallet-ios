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
import Combine
import Moya

// MARK: - RateObject

struct RateObject {
    let code: String
    let name: String
    let price: Decimal
}

// MARK: Equatable

extension RateObject: Equatable {
    static func == (rhs: RateObject, lhs: RateObject) -> Bool {
        let haveEqualCodeObjects = rhs.code == lhs.code

        if !haveEqualCodeObjects {
            return false
        }

        let haveEqualNameObjects = rhs.name == lhs.name
        if !haveEqualNameObjects {
            return false
        }

        let haveEqualPriceObjects = rhs.price == lhs.price

        if !haveEqualPriceObjects {
            return false
        }

        return true
    }
}

// MARK: - RatesProvider

protocol RatesProvider: AnyObject {
    var updateHandler: (([RateObject]) -> Void)? { get set }

    func startExchangeRateFetching()
}

// MARK: - RatesProviderFactory

enum RatesProviderFactory {
    static var base: RatesProvider = BaseRatesProvider.shared
}

// MARK: - CTX rates endpoint

/// The Dash rate aggregator (`rates.ctx.com`, formerly dashretail) — the same
/// primary source DashSync's `DSPriceManager` used. Public, unauthenticated;
/// deliberately NOT `AccessTokenAuthorizable` so `HTTPClient` never demands a
/// bearer token for it.
private enum CTXRatesEndpoint {
    case rates
}

extension CTXRatesEndpoint: TargetType {
    var baseURL: URL { URL(string: "https://rates.ctx.com")! }
    var path: String { "/rates" }
    var method: Moya.Method { .get }
    var task: Moya.Task { .requestParameters(parameters: ["source": "ctx"], encoding: URLEncoding.default) }
    var headers: [String: String]? { nil }
    var sampleData: Data { Data() }
}

/// One row of the CTX response: `[{"symbol":"DASHUSD","price":"12.34"}, …]`.
/// `price` is a STRING (mirrors DashSync's strict parse in
/// `DSHTTPDashRetailOperation`).
private struct CTXRate: Decodable {
    let symbol: String
    let price: String
}

// MARK: - BaseRatesProvider

/// Fetches Dash↔fiat rates directly from CTX (replacing DashSync's
/// `DSPriceManager`), persists them under the same UserDefaults keys for
/// cross-launch cache continuity, and publishes the volatility / fetch-error
/// signals the UI observes. No DashSync involvement.
final class BaseRatesProvider: NSObject, RatesProvider {
    static var shared: BaseRatesProvider = BaseRatesProvider()

    /// Same literal keys DashSync's `DSPriceManager` wrote, so an existing
    /// user's cached rates survive the update (defined app-side now — the
    /// `PRICESBYCODE_KEY` / `LAST_RATES_RETRIEVAL_TIME` DashSync macros are no
    /// longer referenced from here).
    private static let pricesByCodeKey = "DS_PRICEMANAGER_PRICESBYCODE"
    private static let lastRatesRetrievalTimeKey = "DS_LAST_RATES_RETRIEVAL_TIME"

    /// Poll cadence + volatility window, ported verbatim from `DSPriceManager`
    /// (`TICKER_REFRESH_TIME` / `VOLATILE_RATES_CUTTOFF_PERIOD`).
    private static let refreshInterval: TimeInterval = 60
    private static let volatileCutoff: TimeInterval = 7 * 24 * 60 * 60

    private let httpClient = HTTPClient<CTXRatesEndpoint>()

    var updateHandler: (([RateObject]) -> Void)? {
        didSet {
            self.emitRates()
        }
    }

    var lastUpdated: Int {
        get { UserDefaults.standard.integer(forKey: Self.lastRatesRetrievalTimeKey) }
    }

    @Published private(set) var hasFetchError: Bool = false
    @Published private(set) var isVolatile: Bool = false

    func startExchangeRateFetching() {
        updateRates()
    }

    private func updateRates() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.refreshInterval) { [weak self] in
            self?.updateRates()
        }

        fetchPrices()
    }

    private func fetchPrices() {
        // `_Concurrency.Task` disambiguates from `Moya.Task` (both in scope here).
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let raw: [CTXRate] = try await self.httpClient.request(.rates)
                let rates = Self.parse(raw)
                await MainActor.run {
                    self.hasFetchError = false
                    // An empty/all-filtered response must not clobber the cache
                    // (keeps the last good rates on screen), matching DashSync's
                    // reject-invalid-response behavior.
                    guard !rates.isEmpty else { return }
                    self.persistAndEmit(rates)
                }
            } catch {
                await MainActor.run {
                    // Only genuine connectivity failures flip the error flag
                    // (mirrors DashSync's NSURLErrorDomain-only rule); a bad
                    // payload / status just skips this cycle silently.
                    if Self.isNetworkError(error) {
                        self.hasFetchError = true
                    }
                }
            }
        }
    }

    /// Filter to DASH-quoted fiat pairs and map to `RateObject`. Mirrors
    /// `DSHTTPDashRetailOperation`: keep `DASH`-prefixed symbols, strip the
    /// prefix for the currency code, drop non-fiat codes (see `fiatCodes`).
    private static func parse(_ raw: [CTXRate]) -> [RateObject] {
        var out: [RateObject] = []
        out.reserveCapacity(raw.count)
        for row in raw {
            guard row.symbol.hasPrefix("DASH") else { continue }
            let code = String(row.symbol.dropFirst(4))
            guard !code.isEmpty, fiatCodes.contains(code) else { continue }
            guard let price = Decimal(string: row.price) else { continue }
            out.append(RateObject(code: code, name: currencyName(fromCode: code), price: price))
        }
        return out
    }

    @MainActor
    private func persistAndEmit(_ rates: [RateObject]) {
        let defaults = UserDefaults.standard

        // Read the previous local-currency price + last retrieval time BEFORE
        // overwriting — the inputs to the volatility check (DSPriceManager.m).
        let localCode = App.fiatCurrency
        let oldLocalPrice = (defaults.object(forKey: Self.pricesByCodeKey) as? [String: NSNumber])?[localCode]?.doubleValue
        let lastRetrieval = defaults.integer(forKey: Self.lastRatesRetrievalTimeKey)
        let now = Int(Date().timeIntervalSince1970)

        var plainPricesByCode: [String: NSNumber] = [:]
        plainPricesByCode.reserveCapacity(rates.count)
        for rate in rates {
            plainPricesByCode[rate.code] = rate.price as NSDecimalNumber
        }
        defaults.set(plainPricesByCode, forKey: Self.pricesByCodeKey)
        defaults.set(now, forKey: Self.lastRatesRetrievalTimeKey)

        let newLocalPrice = plainPricesByCode[localCode]?.doubleValue
        isVolatile = Self.computeVolatile(lastRetrieval: lastRetrieval, now: now,
                                          oldPrice: oldLocalPrice, newPrice: newLocalPrice)

        updateHandler?(rates)
    }

    /// `isVolatile = (lastRetrieval + 7d > now) && |old − new| > 0.5·old`
    /// (DSPriceManager.m:305 / :615). The time guard is what makes the first
    /// ever fetch non-volatile (`lastRetrieval == 0`), NOT the nil check.
    private static func computeVolatile(lastRetrieval: Int, now: Int,
                                        oldPrice: Double?, newPrice: Double?) -> Bool {
        guard Double(lastRetrieval) + volatileCutoff > Double(now) else { return false }
        guard let oldPrice, let newPrice else { return false }
        return abs(oldPrice - newPrice) > 0.5 * oldPrice
    }

    private static func isNetworkError(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case let MoyaError.underlying(underlying, _) = error { return underlying is URLError }
        return false
    }

    /// Emit the cached rates immediately (on `updateHandler` assignment) so the
    /// UI shows the last known values before the first live fetch returns.
    private func emitRates() {
        if let plainPricesByCode = UserDefaults.standard.object(forKey: Self.pricesByCodeKey) as? [String : NSNumber] {
            let rates = plainPricesByCode.map { code, rate in
                RateObject(code: code, name: Self.currencyName(fromCode: code), price: rate.decimalValue)
            }
            updateHandler?(rates)
        }
    }

    static func currencyName(fromCode code: String) -> String {
        let locale = Locale.current
        let currencyName = locale.localizedString(forCurrencyCode: code)

        return currencyName ?? code
    }

    /// Fiat currency codes DashSync accepted (its bundled `CurrenciesByCode.plist`
    /// key set, 156 entries). Used to drop non-fiat CTX pairs (e.g. `DASHBTC`)
    /// exactly as DashSync did — `Locale.commonISOCurrencyCodes` is unsafe here
    /// (it omits CLF/JEP/SVC/ZWL and varies by OS version).
    private static let fiatCodes: Set<String> = [
        "AED", "AFN", "ALL", "AMD", "ANG", "AOA", "ARS", "AUD", "AWG", "AZN",
        "BAM", "BBD", "BDT", "BGN", "BHD", "BIF", "BMD", "BND", "BOB", "BRL",
        "BSD", "BTN", "BWP", "BYN", "BZD", "CAD", "CDF", "CHF", "CLF", "CLP",
        "CNY", "COP", "CRC", "CUP", "CVE", "CZK", "DJF", "DKK", "DOP", "DZD",
        "EGP", "ETB", "EUR", "FJD", "FKP", "GBP", "GEL", "GHS", "GIP", "GMD",
        "GNF", "GTQ", "GYD", "HKD", "HNL", "HRK", "HTG", "HUF", "IDR", "ILS",
        "INR", "IQD", "IRR", "ISK", "JEP", "JMD", "JOD", "JPY", "KES", "KGS",
        "KHR", "KMF", "KPW", "KRW", "KWD", "KYD", "KZT", "LAK", "LBP", "LKR",
        "LRD", "LSL", "LYD", "MAD", "MDL", "MGA", "MKD", "MMK", "MNT", "MOP",
        "MRU", "MUR", "MVR", "MWK", "MXN", "MYR", "MZN", "NAD", "NGN", "NIO",
        "NOK", "NPR", "NZD", "OMR", "PAB", "PEN", "PGK", "PHP", "PKR", "PLN",
        "PYG", "QAR", "RON", "RSD", "RUB", "RWF", "SAR", "SBD", "SCR", "SDG",
        "SEK", "SGD", "SHP", "SLL", "SOS", "SRD", "STN", "SVC", "SYP", "SZL",
        "THB", "TJS", "TMT", "TND", "TOP", "TRY", "TTD", "TWD", "TZS", "UAH",
        "UGX", "USD", "UYU", "UZS", "VES", "VND", "VUV", "WST", "XAF", "XCD",
        "XOF", "XPF", "YER", "ZAR", "ZMW", "ZWL",
    ]
}
