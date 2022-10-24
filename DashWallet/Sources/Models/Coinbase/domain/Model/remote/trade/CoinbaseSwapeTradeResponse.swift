//
//  CoinbaseSwapeTradeResponse.swift
//  Coinbase
//
//  Created by hadia on 01/06/2022.
//

import Foundation

// MARK: - CoinbaseSwapeTradeResponse
struct CoinbaseSwapeTradeResponse: Codable {
    let data: CoinbaseSwapeTrade?

    enum CodingKeys: String, CodingKey {
        case data
    }
}

// MARK: - DataClass
struct CoinbaseSwapeTrade: Codable {
    let createdAt: Date?
    let displayInputAmount: DisplayInputAmount?
    let id: String?
    let inputAmount, outputAmount, exchangeRate: DisplayInputAmount?
    let unitPrice: CoinbaseSwapeTradeUnitPrice?
    let fee: DisplayInputAmount?
    let status: String?
    let updatedAt: Date?
    let appliedSubscriptionBenefit: Bool?
    let feeWithoutSubscriptionBenefit, subscriptionInfo: JSONNull?

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case displayInputAmount = "display_input_amount"
        case id
        case inputAmount = "input_amount"
        case outputAmount = "output_amount"
        case exchangeRate = "exchange_rate"
        case unitPrice = "unit_price"
        case fee, status
        case updatedAt = "updated_at"
        case appliedSubscriptionBenefit = "applied_subscription_benefit"
        case feeWithoutSubscriptionBenefit = "fee_without_subscription_benefit"
        case subscriptionInfo = "subscription_info"
    }
}

// MARK: - DisplayInputAmount
struct DisplayInputAmount: Codable {
    let amount, currency: String?
}

// MARK: - UnitPrice
struct CoinbaseSwapeTradeUnitPrice: Codable {
    let targetToFiat, targetToSource: DisplayInputAmount?

    enum CodingKeys: String, CodingKey {
        case targetToFiat = "target_to_fiat"
        case targetToSource = "target_to_source"
    }
}

// MARK: - Encode/decode helpers

class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
        return true
    }

    public var hashValue: Int {
        return 0
    }

    public func hash(into hasher: inout Hasher) {
        // No-op
    }

    public init() {}

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

class JSONCodingKey: CodingKey {
    let key: String

    required init?(intValue: Int) {
        return nil
    }

    required init?(stringValue: String) {
        key = stringValue
    }

    var intValue: Int? {
        return nil
    }

    var stringValue: String {
        return key
    }
}

