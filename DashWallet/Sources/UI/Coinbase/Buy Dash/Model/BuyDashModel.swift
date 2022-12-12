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

// MARK: - BuyDashModel

final class BuyDashModel: BaseAmountModel {
    var paymentMethods: [CoinbasePaymentMethod] {
        Coinbase.shared.paymentMethods
    }

    var activePaymentMethod: CoinbasePaymentMethod? {
        selectedPaymentMethod ?? paymentMethods.first
    }

    var dashPriceDisplayString: String {
        let dashAmount = kOneDash
        let dashAmountFormatted = dashAmount.formattedDashAmount

        let priceManger = DSPriceManager.sharedInstance()
        let fiatBalanceFormatted = priceManger.localCurrencyString(forDashAmount: Int64(dashAmount)) ?? NSLocalizedString("Syncing", comment: "Price")

        let displayString = "\(dashAmountFormatted) DASH ≈ \(fiatBalanceFormatted)"
        return displayString
    }

    private var selectedPaymentMethod: CoinbasePaymentMethod?

    override init() {
        super.init()
    }

    public func select(paymentMethod: CoinbasePaymentMethod) {
        selectedPaymentMethod = paymentMethod
    }
}

extension BuyDashModel {
    override var isCurrencySelectorHidden: Bool {
        true
    }
}
