//
//  CoinBaseTransactionResponse.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation
// MARK: - CoinBaseTransactionsResponse
struct CoinbaseTransactionsResponse: Codable {
    let data: CoinbaseTransaction?
}

// MARK: - DataClass
struct CoinbaseTransaction: Codable {
    let id, type, status: String?
    let amount, nativeAmount: Amount?
    let dataDescription: String?
    let createdAt, updatedAt: Date?
    let resource, resourcePath: String?
    let instantExchange: Bool?
    let network: Network?
    let to: To?
    let idem: String?
    let application: Application?
    let details: Details?
    let hideNativeAmount: Bool?

    enum CodingKeys: String, CodingKey {
        case id, type, status, amount
        case nativeAmount = "native_amount"
        case dataDescription = "description"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case resource
        case resourcePath = "resource_path"
        case instantExchange = "instant_exchange"
        case network, to, idem, application, details
        case hideNativeAmount = "hide_native_amount"
    }
}



// MARK: - Application
struct Application: Codable {
    let id, resource, resourcePath: String?

    enum CodingKeys: String, CodingKey {
        case id, resource
        case resourcePath = "resource_path"
    }
}

// MARK: - Details
struct Details: Codable {
    let title, subtitle, header, health: String?
}

// MARK: - Network
struct Network: Codable {
    let status: String?
    let statusDescription: String?
    let hash: String?
    let transactionURL: String?
    let transactionFee, transactionAmount: Amount?
    let confirmations: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case statusDescription = "status_description"
        case hash
        case transactionURL = "transaction_url"
        case transactionFee = "transaction_fee"
        case transactionAmount = "transaction_amount"
        case confirmations
    }
}

// MARK: - To
struct To: Codable {
    let resource, address, currency: String?
    let addressInfo: AddressInfo?
    let addressURL: String?

    enum CodingKeys: String, CodingKey {
        case resource, address, currency
        case addressInfo = "address_info"
        case addressURL = "address_url"
    }
}
