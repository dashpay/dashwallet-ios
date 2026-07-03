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
    let coin: SwapCryptoCurrency

    @Published var inputValue: String = ""
    @Published var selectedCurrency: CurrencyOption
    @Published private(set) var currentFiatCurrency: String
    @Published var isLoading: Bool = false
    @Published var isValidating: Bool = false
    @Published private(set) var rateErrorMessage: String?
    @Published private(set) var validationErrorMessage: String?
    @Published var statusMessage: String?

    private let swapProvider: SwapProvider
    private var amount = SwapConvertAmount()
    private var cancellables = Set<AnyCancellable>()
    private var rateRequestID = 0
    // Monotonically increasing; stale validation responses are ignored after edits.
    private var validationRequestID = 0
    private var isSwitchingCurrency = false

    var title: String {
        NSLocalizedString("Enter amount", comment: "Dash DEX")
    }

    var subtitle: String? { nil }

    var currencyOptions: [CurrencyOption] {
        [.fiat(currentFiatCurrency), .dash, .coin(coin.code)]
    }

    var cryptoAmountString: String {
        Self.formattedCryptoAmount(amount.crypto)
    }

    var isActionEnabled: Bool {
        amount.crypto > 0 && !isValidating
    }

    var inlineMessage: String? {
        validationErrorMessage ?? rateErrorMessage
    }

    init(coin: SwapCryptoCurrency, swapProvider: SwapProvider) {
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
        invalidateValidationState()
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
        let sanitized = Self.sanitize(raw, currency: selectedCurrency)
        if raw != inputValue {
            invalidateValidationState()
        }
        inputValue = sanitized
    }

    func attemptContinue(onSuccess: @escaping (SwapCryptoCurrency, String) -> Void) async {
        guard !isValidating else { return }

        let sellAmount = Self.formattedCryptoAmount(amount.crypto)
        guard !sellAmount.isEmpty else { return }

        let asset = coin.swapAsset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asset.isEmpty else {
            DSLogger.log("Swap: Buy validation skipped for \(coin.code) because the asset is blank")
            onSuccess(coin, sellAmount)
            return
        }

        guard let exampleAddress = coin.exampleAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !exampleAddress.isEmpty else {
            DSLogger.log("Swap: Buy validation skipped for \(coin.code) because no example address is available")
            onSuccess(coin, sellAmount)
            return
        }

        validationRequestID += 1
        let requestID = validationRequestID
        isValidating = true
        validationErrorMessage = nil

        do {
            try await swapProvider.validateBuyOrder(
                sellAsset: asset,
                sellAmount: sellAmount,
                refundAddress: exampleAddress
            )

            guard requestID == validationRequestID else { return }
            isValidating = false
            validationErrorMessage = nil
            onSuccess(coin, sellAmount)
        } catch {
            guard requestID == validationRequestID else { return }
            isValidating = false
            validationErrorMessage = Self.validationMessage(from: error)
        }
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
        rateErrorMessage = nil
        defer {
            if requestID == rateRequestID {
                isLoading = false
                statusMessage = nil
            }
        }

        do {
            let pools = try await swapProvider.fetchPools(direction: .buy)
            guard requestID == rateRequestID else { return }

            guard let pool = pools.first(where: { $0.asset.uppercased() == coin.swapAsset.uppercased() }),
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
            rateErrorMessage = NSLocalizedString(
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
            inputValue = SwapInputFormatter.trimTrailingZeros(String(format: "%.8f", d))
        }
    }

    // MARK: - Private: Validation

    private func parseInput(_ value: String) -> Double? {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        guard let d = Double(normalized), d > 0 else { return nil }
        return d
    }

    private func invalidateValidationState() {
        validationRequestID += 1
        isValidating = false
        validationErrorMessage = nil
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

    private static func formattedCryptoAmount(_ value: Decimal) -> String {
        guard value > 0 else { return "" }

        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, 8, .plain)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8

        return formatter.string(from: rounded as NSDecimalNumber) ?? rounded.string
    }

    private static func validationMessage(from error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if raw.localizedCaseInsensitiveContains("noRoutesFound") {
            return NSLocalizedString("Entered amount is lower than the allowed minimum", comment: "Dash DEX")
        }
        return NSLocalizedString("This amount can't be swapped right now", comment: "Dash DEX")
    }

    private enum RateError: Error {
        case unavailable
    }
}

private enum SwapInputFormatter {
    static func trimTrailingZeros(_ s: String) -> String {
        var result = s
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }
}
