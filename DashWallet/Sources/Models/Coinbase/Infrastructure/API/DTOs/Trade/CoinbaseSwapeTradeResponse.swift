//
//  CoinbaseSwapeTradeResponse.swift
//  Coinbase
//
//  Created by hadia on 01/06/2022.
//

import Foundation

// MARK: - CoinbaseSwapeTrade

struct CoinbaseSwapeTrade: Codable {
    let createdAt: String?
    let displayInputAmount: Amount
    let id: String?
    let inputAmount, outputAmount, exchangeRate: Amount
    let unitPrice: CoinbaseSwapeTradeUnitPrice
    let fee: Amount
    let status: String?
    let updatedAt: String?
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


// MARK: - CoinbaseSwapeTradeUnitPrice

struct CoinbaseSwapeTradeUnitPrice: Codable {
    let targetToFiat: Amount
    let targetToSource: Amount

    enum CodingKeys: String, CodingKey {
        case targetToFiat = "target_to_fiat"
        case targetToSource = "target_to_source"
    }
}

// MARK: - JSONNull

class JSONNull: Codable, Hashable {

    public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
        true
    }

    public var hashValue: Int {
        0
    }

    public func hash(into hasher: inout Hasher) {
        // No-op
    }

    public init() { }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if !container.decodeNil() {
            throw DecodingError.typeMismatch(JSONNull.self,
                                             DecodingError
                                                 .Context(codingPath: decoder.codingPath,
                                                          debugDescription: "Wrong type for JSONNull"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

// MARK: - JSONCodingKey

class JSONCodingKey: CodingKey {
    let key: String

    required init?(intValue: Int) {
        nil
    }

    required init?(stringValue: String) {
        key = stringValue
    }

    var intValue: Int? {
        nil
    }

    var stringValue: String {
        key
    }
}

