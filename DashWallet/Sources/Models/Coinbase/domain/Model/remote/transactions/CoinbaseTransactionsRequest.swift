//
//  CoinBaseTransactionsRequest.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinbaseTransactionsRequest

struct CoinbaseTransactionsRequest: Codable {
    let type: TransactionsType
    let to: String
    let amount: String
    let currency: String
    let idem: UUID
}

// MARK: CoinbaseTransactionsRequest.TransactionsType

extension CoinbaseTransactionsRequest {
    enum TransactionsType: String, Codable {
        case send
        case transfer
        case request
    }
}
