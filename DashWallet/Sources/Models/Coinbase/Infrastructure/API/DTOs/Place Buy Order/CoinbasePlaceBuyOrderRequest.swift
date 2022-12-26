//
//  CoinBasePlaceBuyOrderRequest.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinBasePlaceBuyOrderRequest
public struct CoinbasePlaceBuyOrderRequest: Codable {
    let amount: String
    let currency: String
    let paymentMethod: String
    let commit: Bool?
    let quote: Bool?

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
        case paymentMethod = "payment_method"
        case commit, quote
    }
}
