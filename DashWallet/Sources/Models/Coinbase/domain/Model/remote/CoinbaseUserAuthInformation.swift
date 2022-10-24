//
//  CoinbaseUserAuthInformation.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation
// MARK: - CoinbaseUserAuthInformation
struct CoinbaseUserAuthInformation: Codable {
    let data: CoinbaseUserAuthData?
}

// MARK: - DataClass
struct CoinbaseUserAuthData: Codable {
    let method: String?
    let scopes: [String]?
    let oauthMeta: OauthMeta?

    enum CodingKeys: String, CodingKey {
        case method, scopes
        case oauthMeta = "oauth_meta"
    }
}

// MARK: - OauthMeta
struct OauthMeta: Codable {
    let sendLimitAmount, sendLimitCurrency, sendLimitPeriod: String?

    enum CodingKeys: String, CodingKey {
        case sendLimitAmount = "send_limit_amount"
        case sendLimitCurrency = "send_limit_currency"
        case sendLimitPeriod = "send_limit_period"
    }
}
