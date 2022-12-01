//
//  CoinbaseUserAccountInfo.swift
//  Coinbase
//
//  Created by hadia on 24/05/2022.
//

import Foundation

// MARK: - CoinbaseUserAccountData

struct CoinbaseUserAccountData: Codable, Identifiable {
    let id, name: String
    let primary: Bool
    let type: DatumType
    let currency: Currency
    let balance: Balance
    let createdAt, updatedAt: String?
    let resource: Resource
    let resourcePath: String
    let allowDeposits, allowWithdrawals: Bool
    let rewards: Rewards?
    let rewardsApy: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case primary
        case type
        case currency
        case balance
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case resource
        case resourcePath = "resource_path"
        case allowDeposits = "allow_deposits"
        case allowWithdrawals = "allow_withdrawals"
        case rewards
        case rewardsApy = "rewards_apy"
    }
}

// MARK: - Balance

struct Balance: Codable {
    let amount: String
    let currency: String

    var plainAmount: UInt64 {
        guard let dashNumber = Decimal(string: amount) else {
            return 0
        }

        let duffsNumber = Decimal(DUFFS)
        let plainAmount = dashNumber * duffsNumber
        return NSDecimalNumber(decimal: plainAmount).uint64Value
    }
}

// MARK: - Currency

struct Currency: Codable {
    let code, name, color: String
    let sortIndex, exponent: Int
    let type: CurrencyType
    let addressRegex, assetID, slug, destinationTagName: String?
    let destinationTagRegex: String?

    enum CodingKeys: String, CodingKey {
        case code
        case name
        case color
        case sortIndex = "sort_index"
        case exponent, type
        case addressRegex = "address_regex"
        case assetID = "asset_id"
        case slug
        case destinationTagName = "destination_tag_name"
        case destinationTagRegex = "destination_tag_regex"
    }
}

// MARK: - CurrencyType

enum CurrencyType: String, Codable {
    case crypto
    case fiat
}

// MARK: - Resource

enum Resource: String, Codable {
    case account
}

// MARK: - Rewards

struct Rewards: Codable {
    let apy, formattedApy, label: String

    enum CodingKeys: String, CodingKey {
        case apy
        case formattedApy = "formatted_apy"
        case label
    }
}

// MARK: - DatumType

enum DatumType: String, Codable {
    case fiat
    case wallet
}
