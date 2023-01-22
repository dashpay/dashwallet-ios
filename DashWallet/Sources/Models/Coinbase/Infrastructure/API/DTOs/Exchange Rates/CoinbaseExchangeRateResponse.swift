//
//  CoinbaseExchangeRateResponse.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - DataClass

struct CoinbaseExchangeRate: Codable {
    let currency: String?
    let rates: [String: String]?
}
