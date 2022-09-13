//
//  CoinBaseTransactionsRequest.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinBaseTransactionsRequest
struct CoinbaseTransactionsRequest: Codable {
    let type, to, amount, currency: String?
    let idem: String?
}
