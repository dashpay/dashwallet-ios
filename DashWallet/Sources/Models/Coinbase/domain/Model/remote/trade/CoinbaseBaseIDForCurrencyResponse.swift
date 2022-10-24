//
//  CoinbaseBaseIDForCurrencyResponse.swift
//  Coinbase
//
//  Created by hadia on 01/06/2022.
//

import Foundation
// MARK: - CoinbaseBaseIDForCurrencyResponse
struct CoinbaseBaseIDForCurrencyResponse: Codable {
    let data: [CoinbaseBaseIDForCurrency]?
}

// MARK: - Datum
struct CoinbaseBaseIDForCurrency: Codable {
    let base, baseID: String?
    let unitPriceScale: Int?
    let currency: CoinbaseBaseIdCurrency?
    let prices: Prices?

    enum CodingKeys: String, CodingKey {
        case base
        case baseID = "base_id"
        case unitPriceScale = "unit_price_scale"
        case currency, prices
    }
}

enum CoinbaseBaseIdCurrency: String, Codable {
    case usd = "USD"
}

// MARK: - Prices
struct Prices: Codable {
    let latest: String?
    let latestPrice: LatestPrice?

    enum CodingKeys: String, CodingKey {
        case latest
        case latestPrice = "latest_price"
    }
}

// MARK: - LatestPrice
struct LatestPrice: Codable {
    let amount: Amount?
    let timestamp: Date?
    let percentChange: PercentChange?

    enum CodingKeys: String, CodingKey {
        case amount, timestamp
        case percentChange = "percent_change"
    }
}

// MARK: - PercentChange
struct PercentChange: Codable {
    let hour, day, week, month: Double?
    let year, all: Double?
}
