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

import Foundation
import Combine

@MainActor
final class OrderPreviewViewModel: ObservableObject {
    private enum Layout {
        static let submitCountdownSeconds = 10
    }

    let coin: MayaCryptoCurrency
    let address: String
    let fromDashAmount: String
    let fromFiatAmount: String

    @Published var toAmount: String = "—"
    @Published var purchaseAmount: String = "—"
    @Published var purchaseFiatAmount: String? = nil
    @Published var mayaFee: String = "—"
    @Published var mayaFeeFiatAmount: String? = nil
    @Published var totalAmount: String = "—"
    @Published var executionNetwork: String = "—"
    @Published var remainingSubmitSeconds: Int = Layout.submitCountdownSeconds
    @Published var isSubmitting: Bool = false
    @Published var isRefreshing: Bool = false
    @Published var submitErrorMessage: String? = nil
    @Published var submittedTxId: String? = nil

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
            await refreshQuote()
        }
    }

    func refreshQuote() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let newQuote = try await MayaAPIService.shared.fetchQuote(
                dashSatoshis: dashSatoshis,
                toAsset: coin.mayaAsset,
                destination: address
            )

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

    private func submitSwap() async {
        guard !isSubmitting else { return }

        submittedTxId = nil
        submitErrorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let execution = try resolveExecutionData()
            let tx = try await sendCoinsService.sendMayaSwap(
                vaultAddress: execution.vaultAddress,
                dashAmount: UInt64(dashSatoshis),
                memo: execution.memo
            )
            submittedTxId = tx.txHashHexString
            executionNetwork = execution.executionNetwork
        } catch {
            submitErrorMessage = error.localizedDescription
        }
    }

    private func startCountdown() {
        countdownCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.remainingSubmitSeconds > 0 else { return }
                self.remainingSubmitSeconds -= 1
            }
    }

    private func resetCountdown() {
        remainingSubmitSeconds = Layout.submitCountdownSeconds
    }

    private func applyQuote(_ quote: MayaSwapQuote) {
        let expectedOut = assetAmountFromBaseUnitString(quote.expectedAmountOut) ?? 0
        let fee = assetAmountFromBaseUnitString(quote.fees?.total ?? quote.fees?.outbound) ?? 0
        let total = expectedOut + fee

        toAmount = "\(coin.code) \(formatDecimal(expectedOut, maxFractionDigits: 8))"
        purchaseAmount = toAmount
        mayaFee = fee > 0 ? "\(coin.code) \(formatDecimal(fee, maxFractionDigits: 8))" : "—"
        totalAmount = "\(coin.code) \(formatDecimal(total, maxFractionDigits: 8))"
        executionNetwork = quote.executionNetwork ?? "Maya"
    }

    private func resolveExecutionData() throws -> SwapExecutionData {
        guard let vaultAddress = quote.inboundAddress, !vaultAddress.isEmpty else {
            throw NSError(
                domain: "Maya",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Vault address is missing. Please refresh and try again.", comment: "Maya")]
            )
        }
        guard let memo = quote.memo, !memo.isEmpty else {
            throw NSError(
                domain: "Maya",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Swap memo is missing. Please refresh and try again.", comment: "Maya")]
            )
        }
        return SwapExecutionData(
            vaultAddress: vaultAddress,
            memo: memo,
            executionNetwork: "Maya"
        )
    }

    private func assetAmountFromBaseUnitString(_ raw: String?) -> Decimal? {
        guard let raw, let value = Decimal(string: raw) else { return nil }
        return value / Decimal(100_000_000)
    }

    private func formatDecimal(_ value: Decimal, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
