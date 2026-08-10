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

/// Historical-rate stamping for transaction metadata.
@objc
final class Tx: NSObject {
    private var txUserInfos: TransactionMetadataDAO = TransactionMetadataDAOImpl.shared

    func updateRateIfNeeded(for transaction: Transaction) {
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
            // Stamp the rate only — the tax category stays .unknown
            // (unclassified) so readers keep deriving the live default.
            // Persisting the default here would freeze it before
            // internal-transfer detection settles (restore-scan asset-lock
            // reconstruction lags first observation).
            set(rate: rate, currency: App.fiatCurrency, maximumFractionDigits: maximumFractionDigits,
                for: TransactionMetadata(txHash: transaction.txHashData))
            return
        }

        guard userInfo.rate != nil else {
            set(rate: rate, currency: App.fiatCurrency, maximumFractionDigits: maximumFractionDigits, for: userInfo)
            return
        }
    }

    private func set(rate: Int, currency: String, maximumFractionDigits: Int, for userInfo: TransactionMetadata) {
        var userInfo = userInfo
        userInfo.update(rate: rate, currency: currency, maximumFractionDigits: maximumFractionDigits)
        txUserInfos.update(dto: userInfo)
    }

    @objc
    static let shared = Tx()
}
