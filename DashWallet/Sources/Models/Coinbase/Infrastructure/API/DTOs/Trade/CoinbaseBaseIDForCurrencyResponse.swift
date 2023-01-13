//
//  CoinbaseBaseIDForCurrencyResponse.swift
//  Coinbase
//
//  Created by hadia on 01/06/2022.
//

import Foundation

// MARK: - CoinbaseBaseIDForCurrency

struct CoinbaseBaseIDForCurrency: Codable {
    let base: String
    let baseID: String
    let unitPriceScale: Int
    let currency: String

    enum CodingKeys: String, CodingKey {
        case base
        case baseID = "base_id"
        case unitPriceScale = "unit_price_scale"
        case currency
    }
}

// MARK: - CoinbaseBaseIdCurrency

enum CoinbaseBaseIdCurrency: String, Codable {
    case usd = "USD"
}

// MARK: - Prices

struct Prices: Codable {
    let latest: Double
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
        case amount
        case timestamp
        case percentChange = "percent_change"
    }
}

// MARK: - PercentChange

struct PercentChange: Codable {
    let hour: Double
    let day: Double
    let week: Double
    let month: Double
    let year: Double
    let all: Double
}
