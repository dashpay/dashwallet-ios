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

// MARK: - Transaction

/// This class should be used from UI to obtain transactions. In the future most of the logic from DWHomeModel will migrate here.
/// 'Transactions' object will provade an interface to fetch and monitor transactions
///
@objc
final class Transaction: NSObject {
    public var all: Transaction.Transactions {
        .init()
    }

    private var txUserInfos: TxUserInfoDAO = TxUserInfoDAOImpl.shared

    @objc
    func updateRateIfNeeded(for transaction: DSTransaction) {
        guard let decimalRate = try? CurrencyExchanger.shared.rate(for: App.fiatCurrency) else {
            return
        }

        let nf = NumberFormatter.fiatFormatter(currencyCode: App.fiatCurrency)
        let rate = (decimalRate*Decimal(pow(10, nf.maximumFractionDigits)) as NSDecimalNumber).intValue

        guard let userInfo = txUserInfos.get(by: transaction.txHashData) else {
            set(rate: rate, currency: App.fiatCurrency, for: transaction)
            return
        }

        guard userInfo.fiatAmount != nil else {
            set(rate: rate, currency: App.fiatCurrency, for: userInfo)
            return
        }
    }

    private func set(rate: Int, currency: String, for transaction: DSTransaction) {
        set(rate: rate, currency: currency, for: .init(hash: transaction.txHashData, taxCategory: transaction.defaultTaxCategory()))
    }

    private func set(rate: Int, currency: String, for userInfo: TxUserInfo) {
        userInfo.update(rate: rate, currency: currency)
        txUserInfos.update(dto: userInfo)
    }

    @objc
    static let shared = Transaction()
}

// MARK: Transaction.Transactions

extension Transaction {
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

