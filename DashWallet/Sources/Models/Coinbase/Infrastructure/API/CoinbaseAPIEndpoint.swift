//
//  CoinbaseAPIEndpoint.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation
import Moya

/// BaseUrl API Endpoint
private let kBaseURL = URL(string: "https://api.coinbase.com")!

let authBaseURL = URL(string: "https://coinbase.com")

// MARK: - CoinbaseAPIError

struct CoinbaseAPIError: Codable {
    struct Error: Codable {
        let id: String
        let message: String
        let url: URL
    }

    var errors: [Error]
}

// MARK: - CoinbaseAPI

public enum CoinbaseAPI {
    case userAccount
    case userAuthInformation
    case exchangeRates(String)
    case activePaymentMethods
    case placeBuyOrder(String)
    case commitBuyOrder(String, String)
    case sendCoinsToWallet(accountId: String, verificationCode: String?, dto: CoinbaseTransactionsRequest)
    case getBaseIdForUSDModel(String)
    case swapTrade(CoinbaseSwapeTradeRequest)
    case swapTradeCommit(String)
    case accountAddress(String)
    case createCoinbaseAccountAddress(String)
    case getToken(String)
    case revokeToken
    case signIn
}

// MARK: TargetType

extension CoinbaseAPI: TargetType {
    public var baseURL: URL {
        kBaseURL
    }

    public var path: String {
        switch self {
        case .userAccount: return "/v2/accounts/DASH"
        case .userAuthInformation: return "/v2/user/auth"
        case .exchangeRates(let currency): return "/v2/exchange-rates?currency=\(currency)"
        case .activePaymentMethods: return "/v2/payment-methods"
        case .placeBuyOrder(let accountId): return "/v2/accounts/\(accountId)/buys"
        case .commitBuyOrder(let accountId, let orderID): return "/v2/accounts/\(accountId)/buys/\(orderID)/commit"
        case .sendCoinsToWallet(let accountId): return "/v2/accounts/\(accountId)/transactions"
        case .getBaseIdForUSDModel(let baseCurrency): return "/v2//assets/prices?base=\(baseCurrency)&filter=holdable&resolution=latest"
        case .swapTrade: return "/v2/trades"
        case .swapTradeCommit(let tradeId): return "/v2/trades/\(tradeId)/commit"
        case .accountAddress(let accountId): return "/v2/accounts/\(accountId)/addresses"
        case .createCoinbaseAccountAddress(let accountId): return "/v2/accounts/\(accountId)/addresses"
        case .getToken: return "/oauth/token"
        case .revokeToken: return "/oauth/revoke"
        case .signIn: return "/oauth/authorize"
        }
    }

    public var method: Moya.Method {
        switch self {
        case .getToken, .commitBuyOrder, .placeBuyOrder, .sendCoinsToWallet, .swapTrade, .swapTradeCommit, .createCoinbaseAccountAddress:
            return .post
        default:
            return .get
        }
    }

    public var task: Moya.Task {
        switch self {
        case .getToken(let code):
            var queryItems: [String: Any] = [
                "redirect_uri": Coinbase.redirectUri,
                "code": code,
                "grant_type": Coinbase.grantType,
//                "scope": Coinbase.scope,
//                "meta[send_limit_amount]": Coinbase.send_limit_amount,
//                "meta[send_limit_currency]": Coinbase.send_limit_currency,
//                "meta[send_limit_period]": Coinbase.send_limit_period,
                "account": Coinbase.account,
            ]

            if let value = Coinbase.clientID as? String {
                queryItems["client_id"] = value
            }

            if let value = Coinbase.clientSecret as? String {
                queryItems["client_secret"] = value
            }
            return .requestParameters(parameters: queryItems, encoding: JSONEncoding.default)
        case .sendCoinsToWallet(let _, let _, let dto):
            return .requestJSONEncodable(dto)
        case .swapTrade(let dto):
            return .requestJSONEncodable(dto)
        default:
            return .requestPlain
        }
    }

    public var headers: [String : String]? {
        var headers = ["CB-VERSION": "2021-09-07"]

        // TODO: auth middleware
        //        request.setValue("Bearer \(apiAccessToken)", forHTTPHeaderField: "Authorization")
        switch self {
        case .sendCoinsToWallet(let _, let verificationCode, let _):
            headers["CB-2FA-TOKEN"] = verificationCode
        default:
            break
        }

        return headers
    }
}

extension Moya.Response {
    var error: CoinbaseAPIError? {
        let jsonDecoder = JSONDecoder()

        do {
            let result = try jsonDecoder.decode(CoinbaseAPIError.self, from: data)
            return result
        } catch {
            return nil
        }
    }
}
