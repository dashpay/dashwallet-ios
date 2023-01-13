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
    var selectedAccount: CBAccount?
    weak var delegate: CustodialSwapsModelDelegate?

    override var isSendAllowed: Bool { true }

    override var switcherItems: [AmountInputTypeItem] {
        [
            .init(currencySymbol: kDashCurrency, currencyCode: kDashCurrency),
            .init(currencySymbol: "BTC", currencyCode: "BTC"),
            .init(currencySymbol: localCurrency, currencyCode: "FIAT"),
        ]
    }

    func convert() {
        guard let selectedAccount, let dashAccount = Coinbase.shared.dashAccount else { return }

        Task {
            do {
                let result = try await Coinbase.shared.placeTradeOrder(from: selectedAccount, to: dashAccount, amount: UInt64(amount.plainAmount))

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

    override func checkAmountForErrors() { }
}

// MARK: ConverterViewDataSource

extension CustodialSwapsModel: ConverterViewDataSource {
    var fromItem: ConverterViewSourceItem? {
        guard let selectedAccount else {
            return nil
        }

        return .init(image: .remote(selectedAccount.info.iconURL), title: selectedAccount.info.name, currencyCode: selectedAccount.info.currencyCode,
                     plainAmount: selectedAccount.info.plainAmount)
    }

    var toItem: ConverterViewSourceItem? {
        .init(image: .asset("image.explore.dash.wts.dash"), title: "Dash", currencyCode: kDashCurrency, plainAmount: walletBalance)
    }
}
