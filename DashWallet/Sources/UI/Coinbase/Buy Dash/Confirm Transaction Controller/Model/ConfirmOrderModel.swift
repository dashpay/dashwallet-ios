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

final class ConfirmOrderModel: OrderPreviewModel {
    var transactionDelegate: CoinbaseTransactionDelegate?

    var completionHandle: (() -> Void)?
    var failureHandle: ((ConfirmOrderError) -> Void)?
    var orderChangeHandle: (() -> Void)?
    var showCountdown: Bool = false

//    var order: CoinbasePlaceBuyOrder
    let paymentMethod: CoinbasePaymentMethod

    /// Plain amount in Dash
    let amountToTransfer: UInt64
    private let fiatAmount: Decimal?
    private let feeAmount: Decimal?

    init(paymentMethod: CoinbasePaymentMethod, plainAmount: UInt64) {
        self.paymentMethod = paymentMethod
        amountToTransfer = plainAmount
        
        let fee = UInt64(Double(amountToTransfer) * Coinbase.buyFee)
        fiatAmount = try? Coinbase.shared.currencyExchanger.convertDash(amount: amountToTransfer.dashAmount, to: Coinbase.defaultFiat)
        feeAmount = try? Coinbase.shared.currencyExchanger.convertDash(amount: fee.dashAmount, to: Coinbase.defaultFiat)
    }
    
    func placeOrder() async throws {
        let result = try await Coinbase.shared.placeCoinbaseBuyOrder(amount: amountToTransfer)
        
        if !result.success {
            throw Coinbase.Error.transactionFailed(.message(result.errorResponse?.message ?? result.failureReason))
        }
        
        try await transferFromCoinbase(amount: amountToTransfer, with: nil)
    }

    func retry() { }
}

extension ConfirmOrderModel {
    func formattedValue(for item: ConfirmOrderItem) -> String {
        var value: String = ""

        switch item {
        case .paymentMethod:
            value = paymentMethod.name
        case .purchaseAmount:
            if let amount = fiatAmount {
                value = amount.formattedFiatAmount
            }
        case .feeAmount:
            if let fee = feeAmount {
                value = fee.formattedFiatAmount
            }
        case .totalAmount:
            if let amount = fiatAmount, let fee = feeAmount {
                let total = amount + fee
                value = total.formattedFiatAmount
            }
        case .amountInDash:
            value = amountToTransfer.formattedDashAmount
        }

        return value
    }
}
