//
//  CoinbaseAmount.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - Amount

struct Amount: Codable {
    let amount: String
    let currency: String
}

extension Amount {
    var formattedFiatAmount: String {
        assert(currency != kDashCurrency)

        guard let decimal = amount.decimal() else {
            return "—"
        }

        let numberFormatter = NumberFormatter.fiatFormatter(currencyCode: currency)

        guard let string = numberFormatter.string(from: decimal as NSNumber) else {
            return "—"
        }

        return string
    }

    var formattedDashAmount: String {
        assert(currency == kDashCurrency)

        guard let decimal = amount.decimal() else {
            return "—"
        }

        guard let string = NumberFormatter.dashFormatter.string(from: decimal as NSNumber) else {
            return "—"
        }

        return string
    }
}
