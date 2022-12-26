//
//  CoinbaseUserAuthInformation.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation

// MARK: - CoinbaseUserAuthData

struct CoinbaseUserAuthData: Codable {
    let method: String?
    let scopes: [String]?
    let oauthMeta: OauthMeta?

    enum CodingKeys: String, CodingKey {
        case method
        case scopes
        case oauthMeta = "oauth_meta"
    }
}

// MARK: - OauthMeta

struct OauthMeta: Codable {
    let sendLimitAmount: String?
    let sendLimitCurrency: String?
    let sendLimitPeriod: String?

    enum CodingKeys: String, CodingKey {
        case sendLimitAmount = "send_limit_amount"
        case sendLimitCurrency = "send_limit_currency"
        case sendLimitPeriod = "send_limit_period"
    }
}
