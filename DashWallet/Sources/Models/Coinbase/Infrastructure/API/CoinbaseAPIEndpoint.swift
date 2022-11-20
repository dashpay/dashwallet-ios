//
//  CoinbaseAPIEndpoint.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation
/// BaseUrl API Endpoint
private let baseURL = URL(string: "https://api.coinbase.com/")
let authBaseURL = URL(string: "https://coinbase.com/")

enum APIEndpoint: Endpoint {
    var url: URL {
        return URL(string: path, relativeTo: baseURL)!
    }

    var path: String {
        switch self {
        case let .userAccounts(limit): return "v2/accounts?limit=\(limit)"
        case .userAuthInformation: return "v2/user/auth"
        case let .exchangeRates(currency): return "v2/exchange-rates?currency=\(currency)"
        case .activePaymentMethods: return "v2/payment-methods"
        case let .placeBuyOrder(accountId): return "v2/accounts/\(accountId)/buys"
        case let .commitBuyOrder(accountId, orderID): return "v2/accounts/\(accountId)/buys/\(orderID)/commit"
        case let .sendCoinsToWallet(accountId): return "v2/accounts/\(accountId)/transactions"
        case let .getBaseIdForUSDModel(baseCurrency): return "v2//assets/prices?base=\(baseCurrency)&filter=holdable&resolution=latest"
        case .swapTrade: return "v2/trades"
        case let .swapTradeCommit(tradeId): return "v2/trades/\(tradeId)/commit"
        case let .accountAddress(accountId): return "v2/accounts/\(accountId)/addresses"
        case let .createCoinbaseAccountAddress(accountId): return "v2/accounts/\(accountId)/addresses"
        case .getToken: return "oauth/token"
        case .revokeToken: return "oauth/revoke"
        case .signIn: return "/oauth/authorize"
        }
    }

    case userAccounts(Int)
    case userAuthInformation
    case exchangeRates(String)
    case activePaymentMethods
    case placeBuyOrder(String)
    case commitBuyOrder(String, String)
    case sendCoinsToWallet(String)
    case getBaseIdForUSDModel(String)
    case swapTrade
    case swapTradeCommit(String)
    case accountAddress(String)
    case createCoinbaseAccountAddress(String)
    case getToken
    case revokeToken
    case signIn
}
