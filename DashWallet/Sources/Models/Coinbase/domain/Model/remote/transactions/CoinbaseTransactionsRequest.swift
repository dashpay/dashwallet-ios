//
//  CoinBaseTransactionsRequest.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinBaseTransactionsRequest

struct CoinbaseTransactionsRequest: Codable {
    let type: TransactionsType
    let to: String
    let amount: String
    let currency: String
    let idem: UUID
}

extension CoinbaseTransactionsRequest {
    enum TransactionsType: String {
        case send, transfer, request
    }
}
