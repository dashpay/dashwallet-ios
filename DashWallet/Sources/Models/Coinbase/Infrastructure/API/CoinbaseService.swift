//
//  CoinbaseService.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Combine
import Foundation
import Resolver

protocol CoinbaseService {
    func getUserCoinbaseAccounts(limit: Int) -> AnyPublisher<BaseDataResponse<CoinbaseUserAccountData>, Error>
    func getCoinbaseUserAuthInformation() -> AnyPublisher<CoinbaseUserAuthInformation, Error>
    func getCoinbaseExchangeRates(currency: String) -> AnyPublisher<BaseDataResponse<CoinbaseExchangeRate>, Error>
    func getCoinbaseActivePaymentMethods() -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error>
    func placeCoinbaseBuyOrder(accountId: String, request: CoinbasePlaceBuyOrderRequest) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error>
    func commitCoinbaseBuyOrder(accountId: String, orderID: String) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error>
    func sendCoinsToWallet(accountId: String, verificationCode: String?, request: CoinbaseTransactionsRequest) -> AnyPublisher<BaseDataResponse<CoinbaseTransaction>, Error>
    func getBaseIdForUSDModel(baseCurrency: String) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error>
    func swapTradeCoinbase(request: CoinbaseSwapeTradeRequest) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error>
    func swapTradeCommitCoinbase(tradeId: String) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error>
    func getCoinbaseAccountAddress(accountId: String) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error>
    func createCoinbaseAccountAddress(accountId: String, request: CoinbaseCreateAddressesRequest) -> AnyPublisher<BaseDataResponse<CoinbaseAccountAddress>, Error>
    func getToken(code: String) -> AnyPublisher<CoinbaseToken, Error>
}

class CoinbaseServiceImpl: CoinbaseService {
    @Injected private var restClient: RestClient

    func getToken(code: String) -> AnyPublisher<CoinbaseToken, Error> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "redirect_uri", value: NetworkRequest.redirect_uri),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: NetworkRequest.grant_type),
            URLQueryItem(name: "scope", value: NetworkRequest.scope),
            URLQueryItem(name: "meta[\("send_limit_amount")]", value: "\(NetworkRequest.send_limit_amount)"),
            URLQueryItem(name: "meta[\("send_limit_currency")]", value: NetworkRequest.send_limit_currency),
            URLQueryItem(name: "meta[\("send_limit_period")]", value: NetworkRequest.send_limit_period),
            URLQueryItem(name: "account", value: NetworkRequest.account),
        ]

        if let clientID = NetworkRequest.clientID as? String {
            queryItems.append(URLQueryItem(name: "client_id", value: clientID))
        }

        if let clientSecret = NetworkRequest.clientSecret as? String {
            queryItems.append(URLQueryItem(name: "client_secret", value: clientSecret))
        }

        return restClient.post(APIEndpoint.getToken, using: queryItems)
    }

    func getUserCoinbaseAccounts(limit: Int) -> AnyPublisher<BaseDataResponse<CoinbaseUserAccountData>, Error> {
        restClient.get(APIEndpoint.userAccounts(limit))
    }

    func getCoinbaseUserAuthInformation() -> AnyPublisher<CoinbaseUserAuthInformation, Error> {
        restClient.get(APIEndpoint.userAuthInformation)
    }

    func getCoinbaseExchangeRates(currency: String) -> AnyPublisher<BaseDataResponse<CoinbaseExchangeRate>, Error> {
        restClient.get(APIEndpoint.exchangeRates(currency))
    }

    func getCoinbaseActivePaymentMethods() -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error> {
        restClient.get(APIEndpoint.activePaymentMethods)
    }

    func placeCoinbaseBuyOrder(accountId: String, request: CoinbasePlaceBuyOrderRequest) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error> {
        restClient.post(APIEndpoint.placeBuyOrder(accountId), using: request, using: nil)
    }

    func commitCoinbaseBuyOrder(accountId: String, orderID: String) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error> {
        restClient.post(APIEndpoint.commitBuyOrder(accountId, orderID), using: nil as String?, using: nil)
    }

    func sendCoinsToWallet(accountId: String, verificationCode: String?, request: CoinbaseTransactionsRequest) -> AnyPublisher<BaseDataResponse<CoinbaseTransaction>, Error> {
        restClient.post(APIEndpoint.sendCoinsToWallet(accountId), using: request, using: verificationCode)
    }

    func getBaseIdForUSDModel(baseCurrency: String) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error> {
        restClient.get(APIEndpoint.getBaseIdForUSDModel(baseCurrency))
    }

    func swapTradeCoinbase(request: CoinbaseSwapeTradeRequest) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error> {
        restClient.post(APIEndpoint.swapTrade, using: request, using: nil)
    }

    func swapTradeCommitCoinbase(tradeId: String) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error> {
        restClient.post(APIEndpoint.swapTradeCommit(tradeId), using: nil as String?, using: nil)
    }

    func getCoinbaseAccountAddress(accountId: String) -> AnyPublisher<BaseDataCollectionResponse<CoinbasePaymentMethod>, Error> {
        restClient.get(APIEndpoint.accountAddress(accountId))
    }

    func createCoinbaseAccountAddress(accountId: String, request: CoinbaseCreateAddressesRequest) -> AnyPublisher<BaseDataResponse<CoinbaseAccountAddress>, Error> {
        restClient.post(APIEndpoint.createCoinbaseAccountAddress(accountId), using: request, using: nil)
    }
}
