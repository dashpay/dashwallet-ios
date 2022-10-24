//
//  CoinbaseToken.swift
//  Coinbase
//
//  Created by hadia on 20/06/2022.
//

import Foundation
// MARK: - CoinbaseToken
struct CoinbaseToken: Codable {
    let accessToken, tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let createdAt: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case createdAt = "created_at"
    }
}
