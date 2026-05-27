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
final class OrderPreviewViewModel: ObservableObject {
    private enum Constants {
        static let submitCountdownSeconds = 10
    }

    let coin: MayaCryptoCurrency
    let address: String
    let fromDashAmount: String
    let fromFiatAmount: String

    @Published var toAmount: String = "—"
    @Published var purchaseAmount: String = "—"
    @Published var purchaseFiatAmount: String?
    @Published var mayaFee: String = "—"
    @Published var mayaFeeFiatAmount: String?
    @Published var totalAmount: String = "—"
    @Published var executionNetwork: String = "—"
    @Published var remainingSubmitSeconds: Int = Constants.submitCountdownSeconds
    @Published var isSubmitting: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var submitErrorMessage: String?
    // Records that the Dash transaction was submitted to the blockchain network.
    // This does NOT confirm Maya swap completion — that requires separate on-chain confirmation.
    @Published var submittedTxId: String?

    var confirmButtonText: String {
        if remainingSubmitSeconds > 0 {
            return String(
                format: NSLocalizedString("Confirm (%lds)", comment: "Maya"),
                CLong(remainingSubmitSeconds)
            )
        } else {
            return NSLocalizedString("Refresh quote", comment: "Maya")
        }
    }

    private let dashSatoshis: Int64
    private var quote: MayaSwapQuote
    private var countdownCancellable: AnyCancellable?
    private let sendCoinsService = SendCoinsService()

    init(
        coin: MayaCryptoCurrency,
        address: String,
        dashSatoshis: Int64,
        fromDashAmount: String,
        fromFiatAmount: String,
        initialQuote: MayaSwapQuote
    ) {
        self.coin = coin
        self.address = address
        self.dashSatoshis = dashSatoshis
        self.fromDashAmount = fromDashAmount
        self.fromFiatAmount = fromFiatAmount
        self.quote = initialQuote
        applyQuote(initialQuote)
        startCountdown()
    }

    deinit {
        countdownCancellable?.cancel()
    }

    func handlePrimaryAction() async {
        if remainingSubmitSeconds > 0 {
            await submitSwap()
        } else {
            await refreshQuoteForDisplay()
        }
    }

    // MARK: - Private: Countdown

    private func startCountdown() {
        countdownCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.remainingSubmitSeconds > 0 else { return }
                self.remainingSubmitSeconds -= 1
            }
    }

    private func stopCountdown() {
        countdownCancellable?.cancel()
        countdownCancellable = nil
    }

    private func resetCountdown() {
        remainingSubmitSeconds = Constants.submitCountdownSeconds
    }

    // MARK: - Private: Quote Operations

    private func refreshQuoteForDisplay() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let newQuote = try await fetchFreshQuote()
            if let apiError = newQuote.error {
                submitErrorMessage = apiError
                return
            }
            quote = newQuote
            applyQuote(newQuote)
            resetCountdown()
        } catch {
            submitErrorMessage = error.localizedDescription
        }
    }

    private func fetchFreshQuote() async throws -> MayaSwapQuote {
        try await MayaAPIService.shared.fetchQuote(
            dashSatoshis: dashSatoshis,
            toAsset: coin.mayaAsset,
            destination: address
        )
    }

    private func submitSwap() async {
        guard !isSubmitting else { return }
        submittedTxId = nil
        submitErrorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            // Refresh quote immediately before commit so vault address and memo are fresh.
            // Mirrors Android's getSwapInfo call in MayaBlockchainApi.commitSwapTransaction.
            let freshQuote = try await fetchFreshQuote()
            if let apiError = freshQuote.error {
                setSubmitError(apiError)
                return
            }
            quote = freshQuote
            applyQuote(freshQuote)

            let execution = try resolveExecutionData(from: freshQuote)
            let tx = try await submitDashTransaction(using: execution)
            setSubmittedTransaction(tx)
        } catch {
            setSubmitError(error.localizedDescription)
        }
    }

    private func mayaFieldError(_ message: String) -> Error {
        NSError(domain: "Maya", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func resolveExecutionData(from quote: MayaSwapQuote) throws -> SwapExecutionData {
        guard let vaultAddress = quote.inboundAddress, !vaultAddress.isEmpty else {
            throw mayaFieldError(NSLocalizedString("Vault address is missing. Please refresh and try again.", comment: "Maya"))
        }
        guard let memo = quote.memo, !memo.isEmpty else {
            throw mayaFieldError(NSLocalizedString("Swap memo is missing. Please refresh and try again.", comment: "Maya"))
        }
        return SwapExecutionData(vaultAddress: vaultAddress, memo: memo, executionNetwork: "Maya")
    }

    private func submitDashTransaction(using execution: SwapExecutionData) async throws -> DSTransaction {
        try await sendCoinsService.sendMayaSwap(
            vaultAddress: execution.vaultAddress,
            dashAmount: UInt64(dashSatoshis),
            memo: execution.memo
        )
    }

    // MARK: - Private: State Mutation

    private func setSubmitError(_ message: String) {
        submitErrorMessage = message
    }

    private func setSubmittedTransaction(_ tx: DSTransaction) {
        submittedTxId = tx.txHashHexString
    }

    private func applyQuote(_ quote: MayaSwapQuote) {
        let expectedOut = assetDecimalFromBaseUnits(quote.expectedAmountOut)
        let fee = assetDecimalFromBaseUnits(quote.fees?.total ?? quote.fees?.outbound)
        let total = expectedOut + fee

        toAmount = formatCryptoAmount(expectedOut)
        purchaseAmount = toAmount
        mayaFee = formatFeeAmount(fee)
        totalAmount = formatCryptoAmount(total)
        executionNetwork = quote.executionNetwork ?? "Maya"
    }

    // MARK: - Private: Formatting

    private func assetDecimalFromBaseUnits(_ raw: String?) -> Decimal {
        guard let raw, let value = Decimal(string: raw) else { return 0 }
        return value / Decimal(100_000_000)
    }

    private func formatCryptoAmount(_ value: Decimal) -> String {
        "\(coin.code) \(formatDecimal(value))"
    }

    private func formatFeeAmount(_ value: Decimal) -> String {
        value > 0 ? formatCryptoAmount(value) : "—"
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
