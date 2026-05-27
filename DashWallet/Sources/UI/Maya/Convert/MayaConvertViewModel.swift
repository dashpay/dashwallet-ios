//
//  Created by Roman Chornyi
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

import Combine
import Foundation

@MainActor
final class MayaConvertViewModel: ObservableObject {
    #if DEBUG
    private let isDemoQuoteBypassEnabled = true
    #else
    private let isDemoQuoteBypassEnabled = false
    #endif

    let coin: MayaCryptoCurrency
    let address: String

    @Published var inputValue: String = ""
    @Published var selectedCurrency: CurrencyOption = .localCurrency
    @Published var receiveAmount: String? = nil
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Anchored three-currency amount model (mirrors Android Amount.kt)
    private var amount = MayaConvertAmount()
    private var latestQuote: MayaSwapQuote? = nil

    // Prevents the immediate CombineLatest subscriber from updating the Amount model while
    // we are programmatically syncing inputValue to a derived value during a currency switch.
    private var isSwitchingCurrency = false

    private var cancellables = Set<AnyCancellable>()

    var dashBalance: String {
        DWEnvironment.sharedInstance().currentAccount.balance.formattedDashAmountWithoutCurrencySymbol
    }

    var dashBalanceFiat: String {
        let balance = DWEnvironment.sharedInstance().currentAccount.balance
        return CurrencyExchanger.shared.fiatAmountString(for: balance.dashAmount)
    }

    var currencyOptions: [CurrencyOption] {
        [.localCurrency, .dash, .coin(coin.code)]
    }

    var isActionEnabled: Bool {
        guard let value = Double(inputValue.replacingOccurrences(of: ",", with: ".")),
              value > 0 else { return false }
        return errorMessage == nil
    }

    var canOpenOrderPreview: Bool {
        guard isActionEnabled && !isLoading else { return false }
        return latestQuote != nil
    }

    init(coin: MayaCryptoCurrency, address: String) {
        self.coin = coin
        self.address = address
        initializeRates()
        observeInputChanges()
        observeCurrencySwitch()
        Task { await fetchCryptoRate() }
    }

    func setMax() {
        let balance = DWEnvironment.sharedInstance().currentAccount.balance
        amount.setDash(balance.dashAmount)
        isSwitchingCurrency = true
        syncInputValueForCurrency(selectedCurrency)
        isSwitchingCurrency = false
    }

    func makeOrderPreviewViewModel() -> OrderPreviewViewModel? {
        guard let quote = latestQuote else { return nil }

        return OrderPreviewViewModel(
            coin: coin,
            address: address,
            dashSatoshis: amount.dashSatoshis,
            fromDashAmount: amount.dash.formattedDashAmountWithoutCurrencySymbol,
            fromFiatAmount: formatFiat(amount.fiat),
            initialQuote: quote
        )
    }

    private func initializeRates() {
        let dashFiatRate = (try? CurrencyExchanger.shared.rate(for: App.fiatCurrency)) ?? 1
        amount.dashFiatRate = dashFiatRate
    }

    private func fetchCryptoRate() async {
        do {
            let pools = try await MayaAPIService.shared.fetchPools()
            guard let pool = pools.first(where: { $0.asset.uppercased() == coin.mayaAsset.uppercased() }),
                  let cryptoUsdPrice = pool.priceUSD,
                  cryptoUsdPrice > 0 else { return }

            let dashFiatRate = amount.dashFiatRate
            let dashUsdRate = (try? CurrencyExchanger.shared.rate(for: "USD")) ?? dashFiatRate
            let cryptoFiatRate = Decimal(cryptoUsdPrice) * dashFiatRate / dashUsdRate
            amount.updateRates(dashFiatRate: dashFiatRate, cryptoFiatRate: cryptoFiatRate)

            if case .coin = selectedCurrency {
                syncInputValueForCurrency(selectedCurrency)
            }
        } catch {
            // Ignore: crypto input mode remains unavailable until rates can be fetched.
        }
    }

    private func observeInputChanges() {
        // Recalculate only on actual input edits.
        // Currency switches are handled separately in observeCurrencySwitch().
        $inputValue
            .sink { [weak self] value in
                guard let self, !self.isSwitchingCurrency else { return }
                self.updateAmountModel(input: value, currency: self.selectedCurrency)
            }
            .store(in: &cancellables)

        $inputValue
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.fetchQuoteForCurrentAmount()
            }
            .store(in: &cancellables)
    }

    private func observeCurrencySwitch() {
        $selectedCurrency
            .dropFirst()
            .sink { [weak self] newCurrency in
                guard let self else { return }
                self.isSwitchingCurrency = true
                self.syncInputValueForCurrency(newCurrency)
                self.isSwitchingCurrency = false
            }
            .store(in: &cancellables)
    }

    private func updateAmountModel(input: String, currency: CurrencyOption) {
        let normalized = input.replacingOccurrences(of: ",", with: ".")
        guard let d = Double(normalized), d > 0 else { return }
        let decimal = Decimal(d)

        switch currency {
        case .dash:
            amount.setDash(decimal)
        case .localCurrency:
            amount.setFiat(decimal)
        case .coin:
            guard amount.cryptoFiatRate > 0 else { return }
            amount.setCrypto(decimal)
        }
    }

    private func syncInputValueForCurrency(_ currency: CurrencyOption) {
        switch currency {
        case .dash:
            inputValue = amount.dash.isZero ? "" : amount.dash.formattedDashAmountWithoutCurrencySymbol

        case .localCurrency:
            guard !amount.fiat.isZero else { inputValue = ""; return }
            let d = (amount.fiat as NSDecimalNumber).doubleValue
            inputValue = String(format: "%.2f", d)

        case .coin:
            guard !amount.crypto.isZero, amount.cryptoFiatRate > 0 else { inputValue = ""; return }
            let d = (amount.crypto as NSDecimalNumber).doubleValue
            var s = String(format: "%.8f", d)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
            inputValue = s
        }
    }

    private func fetchQuoteForCurrentAmount() {
        let normalized = inputValue.replacingOccurrences(of: ",", with: ".")
        guard let d = Double(normalized), d > 0 else {
            latestQuote = nil
            receiveAmount = nil
            errorMessage = nil
            return
        }

        if case .coin = selectedCurrency, amount.cryptoFiatRate == 0 {
            latestQuote = nil
            errorMessage = NSLocalizedString("Exchange rate not available", comment: "Maya")
            return
        }

        let dashSatoshis = amount.dashSatoshis
        guard dashSatoshis > 0 else {
            latestQuote = nil
            receiveAmount = nil
            return
        }

        let accountBalance = Int64(DWEnvironment.sharedInstance().currentAccount.balance)
        guard dashSatoshis <= accountBalance else {
            latestQuote = nil
            receiveAmount = nil
            errorMessage = NSLocalizedString("Insufficient balance", comment: "Maya")
            return
        }

        errorMessage = nil
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let quote = try await MayaAPIService.shared.fetchQuote(
                    dashSatoshis: dashSatoshis,
                    toAsset: coin.mayaAsset,
                    destination: address
                )
                if let apiError = quote.error {
                    if isDemoQuoteBypassEnabled {
                        applyDemoQuoteFallback(dashSatoshis: dashSatoshis)
                    } else {
                        latestQuote = nil
                        receiveAmount = nil
                        errorMessage = apiError.contains("not enough asset to pay for fees")
                            ? NSLocalizedString("Amount too small to cover fees", comment: "Maya")
                            : NSLocalizedString("Unable to get a quote", comment: "Maya")
                    }
                } else if let raw = quote.expectedAmountOut,
                          let rawValue = Double(raw) {
                    latestQuote = quote
                    errorMessage = nil
                    let humanReadable = rawValue / 1e8
                    var formatted = String(format: humanReadable < 0.001 ? "%.8f" : "%.4f", humanReadable)
                    while formatted.hasSuffix("0") { formatted.removeLast() }
                    if formatted.hasSuffix(".") { formatted.removeLast() }
                    receiveAmount = "\(coin.code) \(formatted)"
                } else {
                    if isDemoQuoteBypassEnabled {
                        applyDemoQuoteFallback(dashSatoshis: dashSatoshis)
                    } else {
                        latestQuote = nil
                        errorMessage = nil
                        receiveAmount = nil
                    }
                }
            } catch {
                if isDemoQuoteBypassEnabled {
                    applyDemoQuoteFallback(dashSatoshis: dashSatoshis)
                } else {
                    latestQuote = nil
                    errorMessage = nil
                    receiveAmount = nil
                }
            }
        }
    }

    private func applyDemoQuoteFallback(dashSatoshis: Int64) {
        let expectedOutBaseUnits = fallbackExpectedOutBaseUnits(from: dashSatoshis)
        latestQuote = MayaSwapQuote(
            error: nil,
            expectedAmountOut: expectedOutBaseUnits,
            dustThreshold: "0",
            expiry: Int64(Date().timeIntervalSince1970) + 60,
            fees: MayaSwapFees(
                affiliate: "0",
                asset: coin.mayaAsset,
                liquidity: "0",
                outbound: "0",
                slippageBps: 0,
                total: "0",
                totalBps: 0
            ),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: nil,
            notes: "DEMO_BYPASS",
            outboundDelayBlocks: nil,
            outboundDelaySeconds: nil,
            recommendedMinAmountIn: nil,
            slippageBps: 0,
            warning: "DEMO_BYPASS",
            routeId: nil,
            routeProviders: nil,
            executionNetwork: "Maya"
        )

        errorMessage = nil
        let humanReadable = Double(expectedOutBaseUnits).map { $0 / 1e8 } ?? 0
        var formatted = String(format: humanReadable < 0.001 ? "%.8f" : "%.4f", humanReadable)
        while formatted.hasSuffix("0") { formatted.removeLast() }
        if formatted.hasSuffix(".") { formatted.removeLast() }
        receiveAmount = "\(coin.code) \(formatted)"
    }

    private func fallbackExpectedOutBaseUnits(from dashSatoshis: Int64) -> String {
        let fallbackHuman = amount.crypto > 0 ? amount.crypto : (Decimal(dashSatoshis) / Decimal(100_000_000))
        let baseUnits = fallbackHuman * Decimal(100_000_000)
        var rounded = Decimal()
        var mutable = baseUnits
        NSDecimalRound(&rounded, &mutable, 0, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private func formatFiat(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = App.fiatCurrency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
