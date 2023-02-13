//
//  Created by Pavel Tikhonenko
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
import SQLite

extension TxUserInfoTaxCategory {
    var stringValue: String {
        switch self {
        case .unknown:
            return NSLocalizedString("Transfer", comment: "")
        case .transferOut:
            return NSLocalizedString("Transfer Out", comment: "")
        case .transferIn:
            return NSLocalizedString("Transfer In", comment: "")
        case .expense:
            return NSLocalizedString("Expense", comment: "")
        case .income:
            return NSLocalizedString("Income", comment: "")
        }
    }


    var nextTaxCategory: TxUserInfoTaxCategory {
        switch self {
        case .unknown:
            return .unknown
        case .income:
            return .transferIn
        case .transferIn:
            return .income
        case .expense:
            return .transferOut
        case .transferOut:
            return .expense
        }
    }
}

// MARK: - TxUserInfo

@objc class TxUserInfo: NSObject {
    @objc var txHash: Data
    @objc var taxCategory: TxUserInfoTaxCategory = .unknown

    var rate: Int?
    var rateCurrency: String?
    var rateMaximumFractionDigits: Int?

    @objc
    init(hash: Data, taxCategory: TxUserInfoTaxCategory) {
        txHash = hash
    }

    init(row: Row) {
        txHash = row[TxUserInfo.txHashColumn]
        taxCategory = TxUserInfoTaxCategory(rawValue: row[TxUserInfo.txCategoryColumn]) ?? .unknown
        rate = row[TxUserInfo.txRateColumn]
        rateCurrency = row[TxUserInfo.txRateCurrencyCodeColumn]
        rateMaximumFractionDigits = row[TxUserInfo.txRateMaximumFractionDigitsColumn]
        super.init()
    }

    func update(rate: Int, currency: String, maximumFractionDigits: Int) {
        self.rate = rate
        rateCurrency = currency
        rateMaximumFractionDigits = maximumFractionDigits
    }
}

@objc
extension TxUserInfo {
    @objc
    func taxCategoryString() -> String {
        taxCategory.stringValue
    }

    @objc
    func fiatAmountString(from dashAmount: UInt64) -> String {
        let notAvailableString = NSLocalizedString("Not available", comment: "Fiat amount");

        if let rate,
           let rateCurrency,
           let rateMaximumFractionDigits {
            let rate = Decimal(rate)/Decimal(pow(10, rateMaximumFractionDigits))
            let fiatAmount = try? CurrencyExchanger.shared.convertDash(amount: dashAmount.dashAmount,
                                                                       to: rateCurrency,
                                                                       rate: rate)

            if let fiatAmount {
                let nf = NumberFormatter.fiatFormatter(currencyCode: rateCurrency)
                return nf.string(from: fiatAmount as NSDecimalNumber) ?? notAvailableString
            }
        }

        return notAvailableString
    }
}

extension TxUserInfo {
    static var table: Table { Table("tx_userinfo") }
    static var txCategoryColumn: Expression<Int> { Expression<Int>("taxCategory") }
    static var txHashColumn: Expression<Data> { Expression<Data>("txHash") }
    static var txRateColumn: Expression<Int?> { .init("rate") }
    static var txRateCurrencyCodeColumn: Expression<String?> { .init("rateCurrencyCode") }
    static var txRateMaximumFractionDigitsColumn: Expression<Int?> { .init("rateMaximumFractionDigits") }
}

@objc
extension DSTransaction {
    @objc
    func defaultTaxCategory() -> TxUserInfoTaxCategory {
        switch direction() {
        case .moved:
            return .expense
        case .sent:
            return .transferOut
        case .received:
            return .transferIn
        case .notAccountFunds:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    @objc
    func defaultTaxCategoryString() -> String {
        let category = defaultTaxCategory()
        return category.stringValue
    }
}

func pow(_ base:Int, _ power:Int) -> Int {
    var answer = 1
    for _ in 0..<power { answer *= base }
    return answer
}
