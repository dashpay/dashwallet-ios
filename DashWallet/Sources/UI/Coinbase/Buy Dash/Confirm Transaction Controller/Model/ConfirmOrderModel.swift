//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

import UIKit


// MARK: - ConfirmOrderError

enum ConfirmOrderError: Error {
    case error
}

// MARK: - ConfirmOrderModel

final class ConfirmOrderModel: CoinbaseTransactionSendable {
    var transactionDelegate: CoinbaseTransactionDelegate?

    var order: CoinbasePlaceBuyOrder
    let paymentMethod: CoinbasePaymentMethod

    /// Plain amount in Dash
    let plainAmount: UInt64

    var completionHandle: (() -> Void)?
    var failureHandle: ((ConfirmOrderError) -> Void)?
    var orderChangeHandle: (() -> Void)?

    init(order: CoinbasePlaceBuyOrder, paymentMethod: CoinbasePaymentMethod, plainAmount: UInt64) {
        self.order = order
        self.paymentMethod = paymentMethod
        self.plainAmount = plainAmount
    }

    public func placeOrder() {
        guard let orderId = order.id else {
            failureHandle?(.error)
            return
        }

        let amount = plainAmount

        Task { [weak self] in
            do {
                let order = try await Coinbase.shared.commitCoinbaseBuyOrder(orderID: orderId)
                try await self?.transferFromCoinbase(amount: amount, with: nil)
            } catch {
                await MainActor.run { [weak self] in
                    self?.failureHandle?(.error)
                }
            }
        }
    }

    public func retry() {
        Task { [weak self] in
            let order = try await Coinbase.shared.placeCoinbaseBuyOrder(amount: plainAmount, paymentMethod: paymentMethod)
            self?.order = order

            await MainActor.run { [weak self] in
                self?.orderChangeHandle?()
            }
        }
    }
}

extension ConfirmOrderModel {
    func formattedValue(for item: ConfirmOrderItem) -> String {
        let value: String

        switch item {
        case .paymentMethod:
            value = paymentMethod.name
        case .purchaseAmount:
            value = order.subtotal.formattedFiatAmount
        case .feeAmount:
            value = order.fee.formattedFiatAmount
        case .totalAmount:
            value = order.total.formattedFiatAmount
        case .amountInDash:
            value = order.amount.formattedDashAmount
        }

        return value
    }
}
