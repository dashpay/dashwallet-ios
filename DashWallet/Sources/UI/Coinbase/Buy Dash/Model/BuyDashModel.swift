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

// MARK: - BuyDashFailureReason

enum BuyDashFailureReason {
    case unknown
}


// MARK: - BuyDashModel

final class BuyDashModel: CoinbaseAmountModel {
    
    @Published var paymentMethods: [CoinbasePaymentMethod] = []

    var activePaymentMethod: CoinbasePaymentMethod? {
        selectedPaymentMethod ?? paymentMethods.first
    }

    override var isAllowedToContinue: Bool {
        isAmountValidForProceeding
    }

    override var canShowInsufficientFunds: Bool {
        false
    }

    var dashPriceDisplayString: String {
        guard let rate = try? Coinbase.shared.currencyExchanger.rate(for: App.fiatCurrency),
              let fiatBalanceFormatted = localFormatter.string(from: rate as NSNumber) else {
            return NSLocalizedString("Syncing...", comment: "Price")
        }

        let dashAmount = kOneDash
        let dashAmountFormatted = dashAmount.formattedDashAmount

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

    public func validateBuyDash(retryWithDeposit: Bool) async -> Coinbase.Error {
        guard let account = await Coinbase.shared.getUsdAccount() else {
            return Coinbase.Error.general(.noCashAccount)
        }
        
        let amount = amount.plainAmount
        let cashBalanceInDash = account.info.plainAmountInDash
        
        if cashBalanceInDash >= amount {
            let fiatMethod = paymentMethods.first { method in
                method.type == .fiatAccount && method.currency == Coinbase.defaultFiat
            }
            
            guard let method = fiatMethod else {
                return Coinbase.Error.general(.noCashAccount)
            }
            
            select(paymentMethod: method)
        } else if retryWithDeposit {
            let bankAccountMethod = paymentMethods.first { $0.type.isBankAccount }
            
            guard let method = bankAccountMethod else {
                return Coinbase.Error.general(.noPaymentMethods)
            }
            
            select(paymentMethod: method)
        } else {
            return Coinbase.Error.transactionFailed(.notEnoughFunds)
        }
        
        return Coinbase.Error.unknownError
    }
}

extension BuyDashModel {
    override var isCurrencySelectorHidden: Bool {
        true
    }
}
