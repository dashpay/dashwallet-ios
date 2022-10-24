//
//  CoinBasePlaceBuyOrderRequest.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinBasePlaceBuyOrderRequest
struct CoinbasePlaceBuyOrderRequest: Codable {
    let amount, currency, paymentMethod: String?
    let commit, quote: Bool?

    enum CodingKeys: String, CodingKey {
        case amount, currency
        case paymentMethod = "payment_method"
        case commit, quote
    }
}
