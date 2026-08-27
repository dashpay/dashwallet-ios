//
//  CoinbaseToken.swift
//  Coinbase
//
//  Created by hadia on 20/06/2022.
//

import Foundation

// MARK: - CoinbaseToken
struct CoinbaseTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expirationDate: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)

        let expiresIn = try container.decode(Double.self, forKey: .expiresIn)
        expirationDate = Date(timeIntervalSinceNow: expiresIn)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}
