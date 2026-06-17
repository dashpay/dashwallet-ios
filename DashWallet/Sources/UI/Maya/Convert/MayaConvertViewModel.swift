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
    let coin: MayaCryptoCurrency
    let address: String

    @Published var inputValue: String = ""
    @Published var selectedCurrency: CurrencyOption
    @Published private(set) var currentFiatCurrency: String
    @Published var receiveAmount: String?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Types

    private enum ValidationResult {
        case empty
        case insufficientBalance
        case exchangeRateUnavailable
        case valid(dashSatoshis: Int64)
    }

    private struct QuoteRequestSnapshot {
        let id: Int
        let dashSatoshis: Int64
        let selectedCurrency: CurrencyOption
        let enteredCoinAmount: Decimal?
        let isMaxFromBalance: Bool
    }

    // MARK: - Private State

    private var amount = MayaConvertAmount()
    private var latestQuote: MayaSwapQuote?
    private var effectiveSellSatoshis: Int64?
    private var isMaxFromBalance = false
    // Monotonically increasing; stale responses are discarded when their snapshot id no longer matches.
    private var quoteRequestID = 0
    // Suppresses input observation while we programmatically sync the displayed value during a currency switch.
    private var isSwitchingCurrency = false
    // Suppresses amount-model writes while we programmatically update the visible coin input from a quote.
    private var isSyncingQuotedInput = false
    // Prevents a programmatic input sync from immediately triggering another debounced quote request.
    private var suppressNextDebouncedQuoteFetch = false
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var dashBalance: Int64 {
        Int64(DWEnvironment.sharedInstance().currentAccount.balance)
    }

    /// Symbol-free formatted Dash balance (e.g. "1.5") for the convert source row.
    var dashBalanceFormatted: String {
        DWEnvironment.sharedInstance().currentAccount.balance.formattedDashAmountWithoutCurrencySymbol
    }

    var dashBalanceFiat: String {
        let balance = DWEnvironment.sharedInstance().currentAccount.balance
        return CurrencyExchanger.shared.fiatAmountString(for: balance.dashAmount)
    }

    /// Symbol-free Dash amount the user has entered (the amount being converted), shown on the
    /// source row instead of the wallet balance.
    var enteredDashFormatted: String {
        Self.dashRoundedDown(displayDashAmount).formattedDashAmountWithoutCurrencySymbol
    }

    /// Fiat value of the entered amount, in the active fiat currency.
    var enteredFiatFormatted: String {
        MayaInputFormatter.fiat(displayFiatAmount, currencyCode: currentFiatCurrency)
    }

    /// True when nothing meaningful has been entered yet (used to hide the fiat sub-line).
    var enteredAmountIsZero: Bool {
        displayDashAmount.isZero
    }

    var currencyOptions: [CurrencyOption] {
        [.fiat(currentFiatCurrency), .dash, .coin(coin.code)]
    }

    var isActionEnabled: Bool {
        guard parseInput(inputValue) != nil else { return false }
        return errorMessage == nil
    }

    var canOpenOrderPreview: Bool {
        guard isActionEnabled && !isLoading else { return false }
        return latestQuote != nil
    }

    // MARK: - Init

    init(coin: MayaCryptoCurrency, address: String) {
        self.coin = coin
        self.address = address
        let initialFiat = App.fiatCurrency
        self.currentFiatCurrency = initialFiat
        self.selectedCurrency = .fiat(initialFiat)
        initializeRates()
        observeInput()
        observeCurrencySwitch()
        Task { await fetchCryptoRate() }
    }

    // MARK: - Public Actions

    /// Sets the input to the wallet's full balance, preserving the active currency display.
    func setMax() {
        let balance = DWEnvironment.sharedInstance().currentAccount.balance
        amount.setDash(Self.dashRoundedDown(balance.dashAmount))
        isMaxFromBalance = true
        clearQuoteState()
        errorMessage = nil
        isSwitchingCurrency = true
        syncInputValueForCurrency(selectedCurrency)
        isSwitchingCurrency = false
        // The debounced inputValue subscriber fires next, triggering a fresh quote.
    }

    /// Updates the active fiat currency, recalculates amounts, and re-fetches a quote.
    func selectFiatCurrency(_ code: String) {
        guard code != currentFiatCurrency else { return }
        App.shared.fiatCurrency = code
        currentFiatCurrency = code

        let dashFiatRate = (try? CurrencyExchanger.shared.rate(for: code)) ?? 1
        amount.updateRates(dashFiatRate: dashFiatRate, cryptoFiatRate: amount.cryptoFiatRate)

        clearQuoteState()

        // When the picker is already showing fiat, update its identity to the new code so
        // SwiftUI detects the change (fiat(ALL) ≠ fiat(UAH) because CurrencyOption is Hashable).
        if case .fiat = selectedCurrency {
            selectedCurrency = .fiat(code)
        }

        scheduleQuoteFetch()
        Task { await fetchCryptoRate() }
    }

    func setInput(_ raw: String) {
        inputValue = Self.sanitize(raw, currency: selectedCurrency)
    }

    func makeOrderPreviewViewModel() -> OrderPreviewViewModel? {
        guard let quote = latestQuote else { return nil }
        return OrderPreviewViewModel(
            coin: coin,
            address: address,
            dashSatoshis: activeSellSatoshis,
            // Order Preview reflects the real (grossed-up) spend — that's where the fee is shown.
            fromDashAmount: dashAmount(from: activeSellSatoshis).formattedDashAmountWithoutCurrencySymbol,
            fromFiatAmount: MayaInputFormatter.fiat(dashAmount(from: activeSellSatoshis) * amount.dashFiatRate, currencyCode: currentFiatCurrency),
            cryptoFiatRate: amount.cryptoFiatRate,
            fiatCurrencyCode: currentFiatCurrency,
            initialQuote: quote
        )
    }

    // MARK: - Private: Rate Initialisation

    private func initializeRates() {
        let dashFiatRate = (try? CurrencyExchanger.shared.rate(for: currentFiatCurrency)) ?? 1
        amount.dashFiatRate = dashFiatRate
    }

    private func fetchCryptoRate() async {
        do {
            let pools = try await MayaAPIService.shared.fetchPools()
            guard let pool = pools.first(where: { $0.asset.uppercased() == coin.mayaAsset.uppercased() }),
                  let cryptoUsdPrice = pool.priceUSD,
                  cryptoUsdPrice > 0 else { return }

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

            scheduleQuoteFetch()
        } catch {
            // Crypto input mode remains unavailable until rates can be fetched.
        }
    }

    // MARK: - Private: Validation

    private func validate() -> ValidationResult {
        guard parseInput(inputValue) != nil else { return .empty }

        if selectedCurrency.isReceiveTargetMode, amount.cryptoFiatRate == 0 {
            return .exchangeRateUnavailable
        }

        let satoshis = activeSellSatoshis
        guard satoshis > 0 else { return .empty }

        let accountBalance = Int64(DWEnvironment.sharedInstance().currentAccount.balance)
        if satoshis > accountBalance { return .insufficientBalance }

        return .valid(dashSatoshis: satoshis)
    }

    private func checkBalance() {
        let satoshis = activeSellSatoshis
        let accountBalance = Int64(DWEnvironment.sharedInstance().currentAccount.balance)
        errorMessage = satoshis > accountBalance
            ? NSLocalizedString("Insufficient balance", comment: "Maya")
            : nil
    }

    // MARK: - Private: Quote State

    private func clearQuoteState() {
        latestQuote = nil
        receiveAmount = nil
        effectiveSellSatoshis = nil
    }

    private func applySuccessfulQuote(_ quote: MayaSwapQuote) {
        guard let raw = quote.expectedAmountOut, let rawValue = Double(raw) else {
            latestQuote = nil
            errorMessage = nil
            receiveAmount = selectedCurrency.isReceiveTargetMode && !isMaxFromBalance ? fixedCoinReceiveAmount : nil
            return
        }
        latestQuote = quote
        receiveAmount = selectedCurrency.isReceiveTargetMode && !isMaxFromBalance
            ? fixedCoinReceiveAmount
            : "\(coin.code) \(MayaInputFormatter.receiveAmount(rawValue / 1e8))"
        checkBalance()
        syncCoinInputToQuotedReceiveIfNeeded(quote)
    }

    private func applyQuoteError(_ apiError: String) {
        latestQuote = nil
        receiveAmount = nil
        errorMessage = NSLocalizedString("Amount too small to cover fees", comment: "Maya")
    }

    // MARK: - Private: Combine Subscriptions

    private func observeInput() {
        $inputValue
            .sink { [weak self] value in
                guard let self, !self.isSwitchingCurrency else { return }
                guard !self.isSyncingQuotedInput else { return }

                self.isMaxFromBalance = false
                self.clearQuoteState()
                guard self.parseInput(value) != nil else {
                    self.errorMessage = nil
                    return
                }
                self.updateAmountModel(input: value, currency: self.selectedCurrency)
                self.checkBalance()
            }
            .store(in: &cancellables)

        $inputValue
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.suppressNextDebouncedQuoteFetch {
                    self.suppressNextDebouncedQuoteFetch = false
                    return
                }
                self.scheduleQuoteFetch()
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
                // The inputValue change above triggers the debounced quote refresh automatically.
            }
            .store(in: &cancellables)
    }

    // MARK: - Private: Quote Fetching

    private func scheduleQuoteFetch() {
        switch validate() {
        case .empty:
            isLoading = false
            clearQuoteState()
            errorMessage = nil
        case .exchangeRateUnavailable:
            isLoading = false
            clearQuoteState()
            errorMessage = NSLocalizedString("Exchange rate not available", comment: "Maya")
        case .insufficientBalance:
            isLoading = false
            clearQuoteState()
            errorMessage = NSLocalizedString("Insufficient balance", comment: "Maya")
        case .valid(let satoshis):
            errorMessage = nil
            isLoading = true
            quoteRequestID += 1
            let snapshot = QuoteRequestSnapshot(
                id: quoteRequestID,
                dashSatoshis: satoshis,
                selectedCurrency: selectedCurrency,
                enteredCoinAmount: selectedCurrency.isReceiveTargetMode ? amount.crypto : nil,
                isMaxFromBalance: isMaxFromBalance
            )
            Task { await fetchQuote(snapshot: snapshot) }
        }
    }

    private func fetchQuote(snapshot: QuoteRequestSnapshot) async {
        defer {
            if quoteRequestID == snapshot.id { isLoading = false }
        }
        do {
            let firstQuote = try await MayaAPIService.shared.fetchQuote(
                dashSatoshis: snapshot.dashSatoshis,
                toAsset: coin.mayaAsset,
                destination: address
            )
            guard quoteRequestID == snapshot.id else { return }
            if let apiError = firstQuote.error {
                applyQuoteError(apiError)
            } else {
                let resolution = try await resolveQuote(firstQuote, snapshot: snapshot)
                guard quoteRequestID == snapshot.id else { return }
                effectiveSellSatoshis = resolution.effectiveSellSatoshis
                applySuccessfulQuote(resolution.quote)
            }
        } catch {
            guard quoteRequestID == snapshot.id else { return }
            latestQuote = nil
            effectiveSellSatoshis = nil
            errorMessage = NSLocalizedString("Amount too small to cover fees", comment: "Maya")
            receiveAmount = snapshot.selectedCurrency.isReceiveTargetMode && !snapshot.isMaxFromBalance
                ? fixedCoinReceiveAmount
                : nil
        }
    }

    // MARK: - Private: Amount Model

    private func updateAmountModel(input: String, currency: CurrencyOption) {
        guard let d = parseInput(input) else {
            // Empty / zero input: reset the model to 0 so the Dash row and receive reflect 0.
            // Otherwise the previous non-zero amount lingers after the user deletes everything.
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

    private func resolveQuote(_ quote: MayaSwapQuote, snapshot: QuoteRequestSnapshot) async throws -> (quote: MayaSwapQuote, effectiveSellSatoshis: Int64?) {
        if snapshot.isMaxFromBalance {
            return (quote, nil)
        }

        guard snapshot.selectedCurrency.isReceiveTargetMode,
              let enteredCoinAmount = snapshot.enteredCoinAmount,
              enteredCoinAmount > 0,
              let expectedOut = decimalFromBaseUnits(quote.expectedAmountOut),
              expectedOut > 0 else {
            return (quote, nil)
        }

        let firstGuessDash = dashAmount(from: snapshot.dashSatoshis)
        guard firstGuessDash > 0 else {
            return (quote, nil)
        }

        let effectiveRate = expectedOut / firstGuessDash
        guard effectiveRate > 0 else {
            return (quoteWithFixedReceive(quote, enteredCoinAmount: enteredCoinAmount), nil)
        }

        let requiredDash = enteredCoinAmount / effectiveRate
        let requiredSellSatoshis = max(1, satoshisRoundedUp(fromDash: requiredDash))
        guard requiredSellSatoshis > 0 else {
            return (quoteWithFixedReceive(quote, enteredCoinAmount: enteredCoinAmount), nil)
        }

        let resolvedQuote: MayaSwapQuote
        if requiredSellSatoshis != snapshot.dashSatoshis {
            let requote = try await MayaAPIService.shared.fetchQuote(
                dashSatoshis: requiredSellSatoshis,
                toAsset: coin.mayaAsset,
                destination: address
            )
            if requote.error == nil {
                resolvedQuote = requote
            } else {
                resolvedQuote = quote
            }
        } else {
            resolvedQuote = quote
        }

        return (
            quoteWithFixedReceive(resolvedQuote, enteredCoinAmount: enteredCoinAmount),
            requiredSellSatoshis
        )
    }

    private func quoteWithFixedReceive(_ quote: MayaSwapQuote, enteredCoinAmount: Decimal) -> MayaSwapQuote {
        MayaSwapQuote(
            error: quote.error,
            expectedAmountOut: baseUnitsString(fromHumanAmount: enteredCoinAmount),
            dustThreshold: quote.dustThreshold,
            expiry: quote.expiry,
            fees: quote.fees,
            inboundAddress: quote.inboundAddress,
            inboundConfirmationBlocks: quote.inboundConfirmationBlocks,
            inboundConfirmationSeconds: quote.inboundConfirmationSeconds,
            memo: quote.memo,
            notes: quote.notes,
            outboundDelayBlocks: quote.outboundDelayBlocks,
            outboundDelaySeconds: quote.outboundDelaySeconds,
            recommendedMinAmountIn: quote.recommendedMinAmountIn,
            slippageBps: quote.slippageBps,
            warning: quote.warning,
            routeId: quote.routeId,
            routeProviders: quote.routeProviders,
            executionNetwork: quote.executionNetwork
        )
    }

    private func syncInputValueForCurrency(_ currency: CurrencyOption) {
        switch currency {
        case .dash:
            let dash5 = Self.dashRoundedDown(amount.dash)
            inputValue = dash5.isZero ? "" : dash5.formattedDashAmountWithoutCurrencySymbol
        case .fiat:
            guard !amount.fiat.isZero else { inputValue = ""; return }
            let d = (amount.fiat as NSDecimalNumber).doubleValue
            inputValue = String(format: "%.2f", d)
        case .coin:
            if let quotedReceiveInputValue {
                inputValue = quotedReceiveInputValue
                return
            }
            guard !amount.crypto.isZero, amount.cryptoFiatRate > 0 else { inputValue = ""; return }
            let d = (amount.crypto as NSDecimalNumber).doubleValue
            inputValue = MayaInputFormatter.trimTrailingZeros(String(format: "%.8f", d))
        }
    }

    private func parseInput(_ value: String) -> Double? {
        let normalized = value.replacingOccurrences(of: ",", with: ".")
        guard let d = Double(normalized), d > 0 else { return nil }
        return d
    }

    private var activeSellSatoshis: Int64 {
        if !isMaxFromBalance, let effectiveSellSatoshis, effectiveSellSatoshis > 0 {
            return effectiveSellSatoshis
        }
        return amount.dashSatoshis
    }

    private var displayDashAmount: Decimal {
        // Enter Amount's "Dash Wallet" row shows the *entered* amount (e.g. $2), not the grossed-up
        // cost — the fee / real spend appear only on the Order Preview. The grossed-up
        // `activeSellSatoshis` still drives the actual swap, balance validation, and the preview.
        dashAmount(from: amount.dashSatoshis)
    }

    private var displayFiatAmount: Decimal {
        displayDashAmount * amount.dashFiatRate
    }

    private var fixedCoinReceiveAmount: String? {
        guard selectedCurrency.isReceiveTargetMode, amount.crypto > 0 else { return nil }
        let value = (amount.crypto as NSDecimalNumber).doubleValue
        return "\(coin.code) \(MayaInputFormatter.receiveAmount(value))"
    }

    private var quotedReceiveInputValue: String? {
        guard isMaxFromBalance,
              selectedCurrency.isCoinInput,
              let latestQuote,
              let expectedOut = decimalFromBaseUnits(latestQuote.expectedAmountOut),
              expectedOut > 0 else {
            return nil
        }
        let value = (expectedOut as NSDecimalNumber).doubleValue
        return MayaInputFormatter.receiveAmount(value)
    }

    private func dashAmount(from satoshis: Int64) -> Decimal {
        Decimal(satoshis) / Decimal(100_000_000)
    }

    private func satoshisRoundedUp(fromDash dash: Decimal) -> Int64 {
        guard dash > 0 else { return 0 }
        var scaled = dash * Decimal(100_000_000)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .up)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    private func decimalFromBaseUnits(_ raw: String?) -> Decimal? {
        guard let raw,
              let decimal = Decimal(string: raw) else {
            return nil
        }
        return decimal / Decimal(100_000_000)
    }

    private func baseUnitsString(fromHumanAmount amount: Decimal) -> String {
        var scaled = amount * Decimal(100_000_000)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private func syncCoinInputToQuotedReceiveIfNeeded(_ quote: MayaSwapQuote) {
        guard isMaxFromBalance,
              selectedCurrency.isCoinInput,
              let expectedOut = decimalFromBaseUnits(quote.expectedAmountOut),
              expectedOut > 0 else {
            return
        }

        let displayValue = MayaInputFormatter.receiveAmount((expectedOut as NSDecimalNumber).doubleValue)
        guard inputValue != displayValue else { return }

        isSyncingQuotedInput = true
        suppressNextDebouncedQuoteFetch = true
        inputValue = displayValue
        isSyncingQuotedInput = false
    }

    // MARK: - Private: Input Sanitization

    /// Normalizes a raw keyboard string before it reaches the amount model.
    /// Rules:
    ///   - Leading zeros stripped from the integer part: "01" → "1", but "0." and "0.12" stay.
    ///   - Decimal precision capped: fiat → 2 places, dash → 5 places, crypto → 8 places.
    ///   - Empty string and in-progress decimals (e.g. "0.") pass through unchanged.
    /// Dash on the convert screen is shown to at most 5 decimals. Rounds DOWN so a displayed or
    /// Max value never exceeds the real wallet amount.
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
}

private struct MayaInputFormatter {
    static func trimTrailingZeros(_ s: String) -> String {
        var result = s
        while result.hasSuffix("0") { result.removeLast() }
        if result.hasSuffix(".") { result.removeLast() }
        return result
    }

    static func receiveAmount(_ humanValue: Double) -> String {
        let s = String(format: humanValue < 0.001 ? "%.8f" : "%.4f", humanValue)
        return trimTrailingZeros(s)
    }

    static func fiat(_ value: Decimal, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

private extension CurrencyOption {
    /// Fiat and coin input are "receive targets" (entered amount = what you receive, fee grossed up
    /// on top); DASH input stays spend-driven.
    var isReceiveTargetMode: Bool {
        isCoinInput || isFiat
    }
}
