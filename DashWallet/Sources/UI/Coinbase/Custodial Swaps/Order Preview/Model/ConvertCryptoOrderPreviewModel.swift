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

// MARK: - ConvertCryptoOrderPreviewModel

final class ConvertCryptoOrderPreviewModel: OrderPreviewModel {
    var amountToTransfer: UInt64

    var transactionDelegate: CoinbaseTransactionDelegate?

    var completionHandle: (() -> Void)?
    var failureHandle: ((ConfirmOrderError) -> Void)?
    var orderChangeHandle: (() -> Void)?
    var showCountdown: Bool = true

    /// Selected account, origin
    let selectedAccount: CBAccount
    var dashAccount: CBAccount { Coinbase.shared.dashAccount! }

    /// Plain amount in Crypto
    let plainAmount: UInt64


    /// Created order
    var order: CoinbaseSwapeTrade

    init(selectedAccount: CBAccount, plainAmount: UInt64, order: CoinbaseSwapeTrade) {
        self.selectedAccount = selectedAccount
        self.plainAmount = plainAmount
        self.order = order
        amountToTransfer = order.outputAmount.amount.plainDashAmount()!
    }

    func placeOrder() async throws {
        guard let orderId = order.id else {
            failureHandle?(.error)
            return
        }

        let selectedAccount = selectedAccount

        Task { [weak self] in
            do {
                let _ = try await Coinbase.shared.commitTradeOrder(origin: selectedAccount, orderID: orderId)
                try await self?.transferFromCoinbase(amount: amountToTransfer, with: nil)
            } catch {
                await MainActor.run { [weak self] in
                    self?.failureHandle?(.error)
                }
            }
        }
    }

    func retry() {
        guard let dashAccount = Coinbase.shared.dashAccount else { return }

        let selectedAccount = selectedAccount
        let plainAmount = order.inputAmount.amount

        Task { [weak self] in
            self?.order = try await Coinbase.shared.placeTradeOrder(from: selectedAccount, to: dashAccount, amount: plainAmount)

            await MainActor.run { [weak self] in
                self?.orderChangeHandle?()
            }
        }
    }
}

extension ConvertCryptoOrderPreviewModel {
    func formattedValue(for item: ConvertCryptoOrderItem) -> String {
        let value: String

        switch item {
        case .origin, .purchaseAmount:
            let formatter = NumberFormatter.cryptoFormatter(currencyCode: selectedAccount.info.currencyCode, exponent: selectedAccount.info.currency.exponent)
            formatter.minimumFractionDigits = 1
            guard let amount = Decimal(string: order.inputAmount.amount) else { return "—" }
            value = formatter.string(from: amount as NSDecimalNumber) ?? "—"
        case .destination:
            let formatter = NumberFormatter.dashFormatter
            guard let amount = Decimal(string: order.outputAmount.amount) else { return "—" }
            value = formatter.string(from: amount as NSDecimalNumber) ?? "—"
        case .feeAmount:
            value = order.fee.formattedFiatAmount
        case .totalAmount:
            guard let fee = Decimal(string: order.fee.amount),
                  let input = Decimal(string: order.displayInputAmount.amount) else { return "—" }
            let total = fee + input
            let numberFormatter = NumberFormatter.fiatFormatter(currencyCode: order.unitPrice.targetToFiat.currency)

            guard let string = numberFormatter.string(from: total as NSNumber) else {
                return "—"
            }

            value = string
        }

        return value
    }
}
