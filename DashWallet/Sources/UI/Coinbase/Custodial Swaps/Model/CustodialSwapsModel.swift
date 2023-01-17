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

// MARK: - CustodialSwapsModelDelegate

protocol CustodialSwapsModelDelegate: AnyObject {
    func custodialSwapsModelDidPlace(order: CoinbaseSwapeTrade)
}

// MARK: - CustodialSwapsModel

class CustodialSwapsModel: SendAmountModel {
    public var hasAccount: Bool {
        selectedAccount != nil
    }

    public var selectedAccount: CBAccount? {
        didSet {
            if let value = selectedAccount {
                let item = AmountInputItem(currencyName: value.info.currency.name, currencyCode: value.info.currency.code)
                if currentInputItem != .app && currentInputItem != .dash {
                    currentInputItem = item
                }
                inputItems = [.app, .dash, item]
                checkAmountForErrors()
            }
        }
    }

    override var isCurrencySelectorHidden: Bool {
        true
    }

    override var supplementaryCurrencyCode: String {
        currentInputItem.currencyCode == kDashCurrency ? localCurrencyCode : currentInputItem.currencyCode
    }

    private var numberFormatters: [String: NumberFormatter] = [:]
    override var supplementaryNumberFormatter: NumberFormatter {
        guard supplementaryCurrencyCode != localCurrencyCode else { return localFormatter }
        guard let selectedAccount else { return localFormatter }

        guard let nf = numberFormatters[supplementaryCurrencyCode] else {
            let formatter = NumberFormatter.cryptoFormatter(currencyCode: supplementaryCurrencyCode, exponent: selectedAccount.info.currency.exponent)
            numberFormatters[supplementaryCurrencyCode] = formatter
            return formatter
        }

        return nf
    }

    weak var delegate: CustodialSwapsModelDelegate?

    override var isSendAllowed: Bool {
        selectedAccount != nil && amount.plainAmount > 0 && !canShowInsufficientFunds
    }

    override var canShowInsufficientFunds: Bool {
        guard let selectedAccount else { return false }

        let plainAmount = amount.plainAmount
        return plainAmount > selectedAccount.info.plainAmountInDash
    }

    override init() {
        super.init()
    }

    func convert() {
        guard let selectedAccount, let dashAccount = Coinbase.shared.dashAccount else { return }

        Task {
            do {
                guard let originAmount = try? Coinbase.shared.currencyExchanger.convertDash(amount: amount.plainAmount.dashAmount, to: selectedAccount.info.currencyCode) else {
                    return
                }

                let result = try await Coinbase.shared.placeTradeOrder(from: selectedAccount,
                                                                       to: dashAccount,
                                                                       amount: originAmount.string)

                await MainActor.run { [weak self] in
                    self?.delegate?.custodialSwapsModelDidPlace(order: result)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.error = error
                }
            }
        }
    }

    override func selectAllFundsWithoutAuth() {
        guard let selectedAccount else { return }

        let max = AmountObject(localAmountString: selectedAccount.info.balance.amount, fiatCurrencyCode: selectedAccount.info.balance.currency,
                               localFormatter: supplementaryNumberFormatter)
        supplementaryAmount = max
        mainAmount = supplementaryAmount.dashAmount
        amountDidChange()
    }
}

// MARK: ConverterViewDataSource

extension CustodialSwapsModel: ConverterViewDataSource {
    var fromItem: SourceViewDataProvider? {
        guard let selectedAccount else {
            return nil
        }

        return ConverterViewSourceItem(image: .remote(selectedAccount.info.iconURL),
                                       title: selectedAccount.info.name,
                                       subtitle: "Coinbase",
                                       balanceFormatted: selectedAccount.info.balanceFormatted,
                                       fiatBalanceFormatted: selectedAccount.info.fiatBalanceFormatted)
    }

    var toItem: SourceViewDataProvider? {
        ConverterViewSourceItem(image: .asset("image.explore.dash.wts.dash"),
                                title: "Dash",
                                subtitle: "Dash Wallet",
                                balanceFormatted: "", // We no need to show balance
                                fiatBalanceFormatted: "") // We no need to show balance
    }
}
