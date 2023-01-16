//
//  CoinbaseUserAccountInfo.swift
//  Coinbase
//
//  Created by hadia on 24/05/2022.
//

import Foundation

// MARK: - CoinbaseUserAccountData + Equatable

extension CoinbaseUserAccountData: Equatable {
    static func == (lhs: CoinbaseUserAccountData, rhs: CoinbaseUserAccountData) -> Bool {
        lhs.name == rhs.name &&
            lhs.currency.code == rhs.currency.code &&
            lhs.balance.amount == rhs.balance.amount
    }
}

// MARK: - CoinbaseUserAccountData

struct CoinbaseUserAccountData: Codable, Identifiable {
    let id: String
    let name: String
    let primary: Bool
    let type: DatumType
    let currency: Currency
    let balance: Balance
    let createdAt, updatedAt: String?
    let resource: Resource
    let resourcePath: String
    let allowDeposits: Bool
    let allowWithdrawals: Bool
    let rewards: Rewards?
    let rewardsApy: String?

    var iconURL: URL {
        let code = currency.code.lowercased()
        let urlString = "https://raw.githubusercontent.com/jsupa/crypto-icons/main/icons/\(code).png"
        return URL(string: urlString)!
    }

    var balanceString: String {
        balance.amount
    }

    var currencyCode: String {
        currency.code
    }

    var balanceFormatted: String {
        let nf = NumberFormatter.cryptoFormatter(currencyCode: currencyCode, exponent: currency.exponent)
        return nf.string(from: balance.amount.decimal()! as NSNumber)!
    }

    var fiatBalanceFormatted: String {
        guard let fiatAmount = try? Coinbase.shared.currencyExchanger.convert(to: App.fiatCurrency, amount: balance.amount.decimal()!, amountCurrency: balance.currency) else {
            return "Invalid"
        }

        let nf = NumberFormatter.fiatFormatter(currencyCode: App.fiatCurrency)
        return nf.string(from: fiatAmount as NSNumber)!
    }

    var plainAmount: UInt64 {
        guard let dashNumber = Decimal(string: balance.amount) else {
            return 0
        }

        let plainAmount = dashNumber * pow(10, currency.exponent)
        return NSDecimalNumber(decimal: plainAmount).uint64Value
    }

    var plainAmountInDash: UInt64 {
        if currencyCode == kDashCurrency { return plainAmount }

        guard let dashAmount = try? Coinbase.shared.currencyExchanger.convertToDash(amount: balance.amount.decimal()!, currency: currencyCode) else {
            return 0
        }

        return dashAmount.plainDashAmount
    }

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
