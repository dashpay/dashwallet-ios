//
//  CoinbasePaymentMethodsResponse.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinbasePaymentMethodsResponse
struct CoinbasePaymentMethodsResponse: Codable {
    let data: [CoinbasePaymentMethod]?
}

// MARK: - Datum
struct CoinbasePaymentMethod: Codable {
    let id, type, name, currency: String?
    let primaryBuy, primarySell, instantBuy, instantSell: Bool?
    let createdAt, updatedAt: Date?
    let resource, resourcePath, pmsvcID: String?
    let allowBuy, allowSell, allowDeposit, allowWithdraw: Bool?
    let fiatAccount: FiatAccount?
    let verified: Bool?
    let minimumPurchaseAmount: MinimumPurchaseAmount?

    enum CodingKeys: String, CodingKey {
        case id, type, name, currency
        case primaryBuy = "primary_buy"
        case primarySell = "primary_sell"
        case instantBuy = "instant_buy"
        case instantSell = "instant_sell"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case resource
        case resourcePath = "resource_path"
        case pmsvcID = "pmsvc_id"
        case allowBuy = "allow_buy"
        case allowSell = "allow_sell"
        case allowDeposit = "allow_deposit"
        case allowWithdraw = "allow_withdraw"
        case fiatAccount = "fiat_account"
        case verified
        case minimumPurchaseAmount = "minimum_purchase_amount"
    }
}

// MARK: - FiatAccount
struct FiatAccount: Codable {
    let id, resource, resourcePath: String?

    enum CodingKeys: String, CodingKey {
        case id, resource
        case resourcePath = "resource_path"
    }
}

// MARK: - MinimumPurchaseAmount
struct MinimumPurchaseAmount: Codable {
    let amount, currency: String?
}
