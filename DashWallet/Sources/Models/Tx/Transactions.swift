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

// MARK: - Tx

/// This class should be used from UI to obtain transactions. In the future most of the logic from DWHomeModel will migrate here.
/// 'Transactions' object will provade an interface to fetch and monitor transactions
///
@objc
final class Tx: NSObject {
    public var all: Tx.Transactions {
        .init()
    }

    private var txUserInfos: TxUserInfoDAO = TxUserInfoDAOImpl.shared

    @objc
    func updateRateIfNeeded(for transaction: DSTransaction) {
        guard let activationDate = DWGlobalOptions.sharedInstance().dateHistoricalRatesActivated,
              transaction.date > activationDate else {
            return
        }

        guard let decimalRate = try? CurrencyExchanger.shared.rate(for: App.fiatCurrency) else {
            return
        }

        let maximumFractionDigits = decimalRate.fractionDigits
        let rate = (decimalRate*pow(10, maximumFractionDigits) as NSDecimalNumber).intValue

        guard let userInfo = txUserInfos.get(by: transaction.txHashData) else {
            set(rate: rate, currency: App.fiatCurrency, maximumFractionDigits: maximumFractionDigits, for: transaction)
            return
        }

        guard userInfo.rate != nil else {
            set(rate: rate, currency: App.fiatCurrency, maximumFractionDigits: maximumFractionDigits, for: userInfo)
            return
        }
    }

    private func set(rate: Int, currency: String, maximumFractionDigits: Int, for transaction: DSTransaction) {
        set(rate: rate, currency: currency, maximumFractionDigits: maximumFractionDigits, for: .init(hash: transaction.txHashData, taxCategory: transaction.defaultTaxCategory()))
    }

    private func set(rate: Int, currency: String, maximumFractionDigits: Int, for userInfo: TxUserInfo) {
        userInfo.update(rate: rate, currency: currency, maximumFractionDigits: maximumFractionDigits)
        txUserInfos.update(dto: userInfo)
    }

    @objc
    static let shared = Tx()
}

// MARK: Tx.Transactions

extension Tx {
    struct Transactions: AsyncSequence, AsyncIteratorProtocol {
        // Obtain all transactions here and monitor for the new ones

        typealias Element = DSTransaction

        mutating func next() async throws -> Element? {
            guard !Task.isCancelled else {
                return nil
            }

            return nil
        }

        func makeAsyncIterator() -> Transactions {
            self
        }
    }
}

