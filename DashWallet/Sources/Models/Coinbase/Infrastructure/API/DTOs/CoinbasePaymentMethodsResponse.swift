//
//  CoinbasePaymentMethodsResponse.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation


// MARK: - CoinbasePaymentMethod

struct CoinbasePaymentMethod: Codable {
    let id: String?
    let type: String?
    let name: String?
    let currency: String?
    let primaryBuy: Bool?
    let primarySell: Bool?
    let instantBuy: Bool?
    let instantSell: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let resource: String?
    let resourcePath: String?
    let pmsvcID: String?
    let allowBuy: Bool?
    let allowSell: Bool?
    let allowDeposit: Bool?
    let allowWithdraw: Bool?
    let fiatAccount: FiatAccount?
    let verified: Bool?
    let minimumPurchaseAmount: MinimumPurchaseAmount?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case currency
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
        case id
        case resource
        case resourcePath = "resource_path"
    }
}

// MARK: - MinimumPurchaseAmount

struct MinimumPurchaseAmount: Codable {
    let amount, currency: String?
}