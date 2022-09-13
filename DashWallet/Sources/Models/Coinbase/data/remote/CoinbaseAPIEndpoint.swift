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
        return URL(string: self.path, relativeTo: baseURL)!
    }
    
    var path: String {
        switch self {
        case .userAccounts(let limit): return "v2/accounts?limit=\(limit)"
        case .userAuthInformation: return "v2/user/auth"
        case .exchangeRates(let currency): return "v2/exchange-rates?currency=\(currency)"
        case .activePaymentMethods: return "v2/payment-methods"
        case .placeBuyOrder(let accountId): return "v2/accounts/\(accountId)/buys"
        case .commitBuyOrder(let accountId,let orderID): return "v2/accounts/\(accountId)/buys/\(orderID)/commit"
        case .sendCoinsToWallet(let accountId): return "v2/accounts/\(accountId)/transactions"
        case .getBaseIdForUSDModel(let baseCurrency): return "v2//assets/prices?base=\(baseCurrency)&filter=holdable&resolution=latest"
        case .swapTrade: return "v2/trades"
        case .swapTradeCommit(let tradeId): return "v2/trades/\(tradeId)/commit"
        case .accountAddress(let accountId): return "v2/accounts/\(accountId)/addresses"
        case .createAccountAddress(let accountId): return "v2/accounts/\(accountId)/addresses"
        case .getToken : return "oauth/token"
        case .revokeToken: return "oauth/revoke"
        case .signIn: return "/oauth/authorize"
    }
}
    
    case userAccounts(Int)
    case userAuthInformation
    case exchangeRates(String)
    case activePaymentMethods
    case placeBuyOrder(String)
    case commitBuyOrder(String,String)
    case sendCoinsToWallet(String)
    case getBaseIdForUSDModel(String)
    case swapTrade
    case swapTradeCommit(String)
    case accountAddress(String)
    case createAccountAddress(String)
    case getToken
    case revokeToken
    case signIn
}
