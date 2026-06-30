//
//  BuyEnterAmountViewModel.swift
//  DashWallet
//
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
import DashUIKit
import Foundation

@MainActor
final class BuyEnterAmountViewModel: ObservableObject {
    let coin: MayaCryptoCurrency

    @Published var inputValue: String = ""
    @Published var selectedCurrency: CurrencyOption
    @Published private(set) var currentFiatCurrency: String
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let swapProvider: SwapProvider
    private var amount = SwapConvertAmount()
    private var cancellables = Set<AnyCancellable>()
    private var rateRequestID = 0
    private var isSwitchingCurrency = false

    var title: String {
        NSLocalizedString("Enter amount", comment: "Dash DEX")
    }

    var subtitle: String? { nil }

    var currencyOptions: [CurrencyOption] {
        [.fiat(currentFiatCurrency), .dash, .coin(coin.code)]
    }

    var isActionEnabled: Bool {
        parseInput(inputValue) != nil && errorMessage == nil
    }

    init(coin: MayaCryptoCurrency, swapProvider: SwapProvider) {
        self.coin = coin
        self.swapProvider = swapProvider
        let initialFiat = App.fiatCurrency
        self.currentFiatCurrency = initialFiat
        self.selectedCurrency = .fiat(initialFiat)
        initializeRates()
        observeInput()
        observeCurrencySwitch()
        Task { await fetchCryptoRate() }
    }

    func selectFiatCurrency(_ code: String) {
        guard code != currentFiatCurrency else { return }
        App.shared.fiatCurrency = code
        currentFiatCurrency = code

        let dashFiatRate = (try? CurrencyExchanger.shared.rate(for: code)) ?? 1
        amount.updateRates(dashFiatRate: dashFiatRate, cryptoFiatRate: amount.cryptoFiatRate)

        if case .fiat = selectedCurrency {
            selectedCurrency = .fiat(code)
        }

        Task { await fetchCryptoRate() }
    }

    func setInput(_ raw: String) {
        inputValue = Self.sanitize(raw, currency: selectedCurrency)
    }

    // MARK: - Private: Rate setup

    private func initializeRates() {
        let dashFiatRate = (try? CurrencyExchanger.shared.rate(for: currentFiatCurrency)) ?? 1
        amount.dashFiatRate = dashFiatRate
    }

    private func fetchCryptoRate() async {
        rateRequestID += 1
        let requestID = rateRequestID

        isLoading = true
        statusMessage = NSLocalizedString("Loading rates…", comment: "Dash DEX")
        errorMessage = nil
        defer {
            if requestID == rateRequestID {
                isLoading = false
                statusMessage = nil
            }
        }

        do {
            let pools = try await swapProvider.fetchPools(direction: .buy)
            guard requestID == rateRequestID else { return }

            guard let pool = pools.first(where: { $0.asset.uppercased() == coin.mayaAsset.uppercased() }),
                  let cryptoUsdPrice = pool.priceUSD,
                  cryptoUsdPrice > 0 else {
                throw RateError.unavailable
            }

            let fiatCurrency = currentFiatCurrency
            let freshDashFiatRate = (try? CurrencyExchanger.shared.rate(for: fiatCurrency)) ?? amount.dashFiatRate
            let dashUsdRate = (try? CurrencyExchanger.shared.rate(for: "USD")) ?? freshDashFiatRate
            let cryptoFiatRate = Decimal(cryptoUsdPrice) * freshDashFiatRate / dashUsdRate
            amount.updateRates(dashFiatRate: freshDashFiatRate, cryptoFiatRate: cryptoFiatRate)

            if case .coin = selectedCurrency {
                isSwitchingCurrency = true
                syncInputValueForCurrency(selectedCurrency)
                isSwitchingCurrency = false
            }
        } catch {
            guard requestID == rateRequestID else { return }
            errorMessage = NSLocalizedString(
                "Unable to load rate data",
                comment: "Dash DEX"
            )
        }
    }

    // MARK: - Private: Observation

    private func observeInput() {
        $inputValue
            .sink { [weak self] value in
                guard let self, !self.isSwitchingCurrency else { return }

                guard self.parseInput(value) != nil else {
                    self.amount.setDash(0)
                    return
                }

                self.updateAmountModel(input: value, currency: self.selectedCurrency)
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

    // MARK: - Private: Amount handling

    private func updateAmountModel(input: String, currency: CurrencyOption) {
        guard let d = parseInput(input) else {
            amount.setDash(0)
            return
        }

        let decimal = Decimal(d)
        switch currency {
        case .dash:
            amount.setDash(decimal)
        case .fiat:
            amount.setFiat(decimal)
        case .coin:
            guard amount.cryptoFiatRate > 0 else { return }
            amount.setCrypto(decimal)
        }
    }

    private func syncInputValueForCurrency(_ currency: CurrencyOption) {
        switch currency {
        case .dash:
            let dash5 = Self.dashRoundedDown(amount.dash)
            inputValue = dash5.isZero ? "" : dash5.formattedDashAmountWithoutCurrencySymbol
        case .fiat:
            guard !amount.fiat.isZero else {
                inputValue = ""
                return
            }
            let d = (amount.fiat as NSDecimalNumber).doubleValue
            inputValue = String(format: "%.2f", d)
        case .coin:
            guard !amount.crypto.isZero, amount.cryptoFiatRate > 0 else {
                inputValue = ""
                return
            }
            let d = (amount.crypto as NSDecimalNumber).doubleValue
            inputValue = MayaInputFormatter.trimTrailingZeros(String(format: "%.8f", d))
        }
    }

    // MARK: - Private: Validation

    private func parseInput(_ value: String) -> Double? {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        guard let d = Double(normalized), d > 0 else { return nil }
        return d
    }

    // MARK: - Private: Sanitization

    static func dashRoundedDown(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 5, .down)
        return result
    }

    private static func sanitize(_ raw: String, currency: CurrencyOption) -> String {
        guard !raw.isEmpty else { return raw }

        let s = raw.replacingOccurrences(of: ",", with: ".")
        let maxDecimals: Int
        switch currency {
        case .fiat: maxDecimals = 2
        case .dash: maxDecimals = 5
        case .coin: maxDecimals = 8
        }

        if let dotRange = s.range(of: ".") {
            let intPart = String(s[s.startIndex..<dotRange.lowerBound])
            let decPart = String(s[dotRange.upperBound...].prefix(maxDecimals))
            return normalizeLeadingZeros(intPart) + "." + decPart
        }
        return normalizeLeadingZeros(s)
    }

    private static func normalizeLeadingZeros(_ s: String) -> String {
        if s.isEmpty { return "0" }
        var result = s
        while result.count > 1, result.hasPrefix("0") { result.removeFirst() }
        return result
    }

    private enum RateError: Error {
        case unavailable
    }
}

private enum MayaInputFormatter {
    static func trimTrailingZeros(_ s: String) -> String {
        var result = s
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}
