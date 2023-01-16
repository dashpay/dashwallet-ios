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

import Foundation

// MARK: - BuyDashModelDelegate

protocol BuyDashModelDelegate: AnyObject {
    func buyDashModelDidPlace(order: CoinbasePlaceBuyOrder)
    func buyDashModelFailedToPlaceOrder(with error: Coinbase.Error)
}

// MARK: - BuyDashFailureReason

enum BuyDashFailureReason {
    case unknown
}


// MARK: - BuyDashModel

final class BuyDashModel: BaseAmountModel {

    weak var delegate: BuyDashModelDelegate?

    var canContinue: Bool {
        amount.plainAmount > 0
    }

    @Published var paymentMethods: [CoinbasePaymentMethod] = []

    var activePaymentMethod: CoinbasePaymentMethod? {
        selectedPaymentMethod ?? paymentMethods.first
    }

    var dashPriceDisplayString: String {
        let dashAmount = kOneDash
        let dashAmountFormatted = dashAmount.formattedDashAmount

        let priceManger = DSPriceManager.sharedInstance()
        let fiatBalanceFormatted = priceManger.localCurrencyString(forDashAmount: Int64(dashAmount)) ?? NSLocalizedString("Syncing", comment: "Price")

        let displayString = "\(dashAmountFormatted) ≈ \(fiatBalanceFormatted)"
        return displayString
    }

    private var selectedPaymentMethod: CoinbasePaymentMethod?

    override init() {
        super.init()

        Task {
            paymentMethods = try await Coinbase.shared.paymentMethods
        }
    }

    public func select(paymentMethod: CoinbasePaymentMethod) {
        selectedPaymentMethod = paymentMethod
    }

    public func buy() {
        guard let paymentMethod = activePaymentMethod else {
            return
        }

        let amount = amount.plainAmount
        Task {
            do {
                let order = try await Coinbase.shared.placeCoinbaseBuyOrder(amount: amount, paymentMethod: paymentMethod)
                await MainActor.run { [weak self] in
                    self?.delegate?.buyDashModelDidPlace(order: order)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.error = error
                }
            }
        }
    }

    override func amountDidChange() {
        error = nil
        super.amountDidChange()
    }
}

extension BuyDashModel {
    override var isCurrencySelectorHidden: Bool {
        true
    }
}
