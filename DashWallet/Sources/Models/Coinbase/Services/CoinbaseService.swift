//
//  CoinbaseService.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Combine
import Foundation
import Moya

// MARK: - CoinbaseService

class CoinbaseService {
    private lazy var httpClient = HTTPClient<CoinbaseAPI>()
}

extension CoinbaseService {
    var OAuth2URL: URL! {
        let path = CoinbaseAPI.signIn.path

        var queryItems = [
            URLQueryItem(name: "redirect_uri", value: Coinbase.redirectUri),
            URLQueryItem(name: "response_type", value: Coinbase.responseType),
            URLQueryItem(name: "scope", value: Coinbase.scope),
            URLQueryItem(name: "meta[send_limit_amount]", value: "\(Coinbase.send_limit_amount)"),
            URLQueryItem(name: "meta[send_limit_currency]", value: Coinbase.send_limit_currency),
            URLQueryItem(name: "meta[send_limit_period]", value: Coinbase.send_limit_period),
            URLQueryItem(name: "account", value: Coinbase.account),
        ]

        if let clientID = Coinbase.clientID as? String {
            queryItems.append(URLQueryItem(name: "client_id", value: clientID))
        }

        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "coinbase.com"
        urlComponents.path = path
        urlComponents.queryItems = queryItems

        guard let url = urlComponents.url else {
            fatalError("URL must be valid")
            return nil
        }

        return url
    }
}

extension CoinbaseService {
    func authorize(code: String) async throws -> CoinbaseToken {
        let result: CoinbaseToken = try await httpClient.request(.getToken(code))
        Coinbase.accessToken = result.accessToken
        Coinbase.refreshToken = result.refreshToken
        return result
    }

    func account() async throws -> CoinbaseUserAccountData {
        let result: BaseDataResponse<CoinbaseUserAccountData> = try await httpClient.request(.userAccount)
        return result.data
    }

    func getCoinbaseUserAuthInformation() async throws -> CoinbaseUserAuthInformation {
        try await httpClient.request(.userAuthInformation)
    }

    func getCoinbaseExchangeRates(currency: String) async throws -> CoinbaseExchangeRate {
        let result: BaseDataResponse<CoinbaseExchangeRate> = try await httpClient.request(.exchangeRates(currency))
        return result.data
    }

    func getCoinbaseActivePaymentMethods() async throws -> [CoinbasePaymentMethod] {
        let result: BaseDataCollectionResponse<CoinbasePaymentMethod> = try await httpClient.request(.activePaymentMethods)
        return result.data
    }

    func placeCoinbaseBuyOrder(accountId: String, request: CoinbasePlaceBuyOrderRequest) async throws -> [CoinbasePlaceBuyOrder] {
        let result: BaseDataCollectionResponse<CoinbasePlaceBuyOrder> = try await httpClient.request(.placeBuyOrder(accountId))
        return result.data
    }

    func commitCoinbaseBuyOrder(accountId: String, orderID: String) async throws -> [CoinbasePlaceBuyOrder] {
        let result: BaseDataCollectionResponse<CoinbasePlaceBuyOrder> = try await httpClient.request(.commitBuyOrder(accountId, orderID))
        return result.data
    }

    func send(amount: String, to address: String, verificationCode: String?) async throws -> [CoinbaseTransaction] {
        guard let coinbaseUserAccountId = Coinbase.coinbaseUserAccountId else {
            throw Coinbase.Error.noActiveUser
        }

        let dto = CoinbaseTransactionsRequest(type: .send,
                                              to: address,
                                              amount: amount,
                                              currency: kDashCurrency,
                                              idem: UUID())

        let result: BaseDataCollectionResponse<CoinbaseTransaction> = try await httpClient
            .request(.sendCoinsToWallet(accountId: coinbaseUserAccountId, verificationCode: verificationCode, dto: dto))
        return result.data
    }

    func getCoinbaseBaseIDForCurrency(baseCurrency: String) async throws -> BaseDataCollectionResponse<CoinbaseBaseIDForCurrency> {
        try await httpClient.request(.getBaseIdForUSDModel(baseCurrency))
    }

    func swapTradeCoinbase(dto: CoinbaseSwapeTradeRequest) async throws -> BaseDataCollectionResponse<CoinbaseSwapeTrade> {
        try await httpClient.request(.swapTrade(dto))
    }

    func swapTradeCommitCoinbase(tradeId: String) async throws -> BaseDataCollectionResponse<CoinbaseSwapeTrade> {
        try await httpClient.request(.swapTradeCommit(tradeId))
    }

    func createCoinbaseAccountAddress(accountId: String) async throws -> String {
        let result: BaseDataResponse<CoinbaseAccountAddress> = try await httpClient.request(.createCoinbaseAccountAddress(accountId))
        return result.data.address
    }
}
