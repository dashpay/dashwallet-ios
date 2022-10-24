//
//  CoinbaseSwapeTradeRequest.swift
//  Coinbase
//
//  Created by hadia on 01/06/2022.
//

import Foundation
// MARK: - CoinbaseSwapeTradeRequest
struct CoinbaseSwapeTradeRequest: Codable {
    let amount, amountAsset, amountFrom, targetAsset: String?
    let sourceAsset: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case amountAsset = "amount_asset"
        case amountFrom = "amount_from"
        case targetAsset = "target_asset"
        case sourceAsset = "source_asset"
    }
}
