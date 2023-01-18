//
//  CoinbaseSwapeTradeRequest.swift
//  Coinbase
//
//  Created by hadia on 01/06/2022.
//

import Foundation

// MARK: - CoinbaseSwapeTradeRequest
public struct CoinbaseSwapeTradeRequest: Codable {
    let amount: String
    let amountAsset: String
    let amountFrom = "input"
    let targetAsset: String
    let sourceAsset: String

    enum CodingKeys: String, CodingKey {
        case amount
        case amountAsset = "amount_asset"
        case amountFrom = "amount_from"
        case targetAsset = "target_asset"
        case sourceAsset = "source_asset"
    }
}
