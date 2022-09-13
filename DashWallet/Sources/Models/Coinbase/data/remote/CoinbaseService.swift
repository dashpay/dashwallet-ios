//
//  CoinbaseService.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation
import Combine
import Resolver

protocol CoinbaseService {
    func getUserCoinbaseAccounts(limit: Int) -> AnyPublisher<CoinbaseUserAccountsResponse, Error>
    func getCoinbaseUserAuthInformation() -> AnyPublisher<CoinbaseUserAuthInformation, Error>
    func getCoinbaseExchangeRates(currency:String) -> AnyPublisher<CoinbaseExchangeRateResponse, Error>
    func getCoinbaseActivePaymentMethods() -> AnyPublisher<CoinbasePaymentMethodsResponse, Error>
    func placeCoinbaseBuyOrder(accountId:String,request: CoinbasePlaceBuyOrderRequest) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error>
    func commitCoinbaseBuyOrder(accountId:String,orderID: String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error>
    func sendCoinsToWallet(accountId:String,api2FATokenVersion:String,request: CoinbaseTransactionsRequest) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error>
    func getBaseIdForUSDModel(baseCurrency:String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error>
    func swapTradeCoinbase(request:CoinbaseSwapeTradeRequest) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error>
    func swapTradeCommitCoinbase(tradeId:String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error>
    func getCoinbaseAccountAddress(accountId:String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error>
    func getToken(code:String) -> AnyPublisher<CoinbaseToken, Error>
}


class CoinbaseServiceImpl: CoinbaseService {
    
    @Injected private var restClient: RestClient
    
    func getToken(code: String) -> AnyPublisher<CoinbaseToken, Error> {
        
        var queryItems : [URLQueryItem] = [
            URLQueryItem(name: "redirect_uri", value: NetworkRequest.redirect_uri),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "grant_type", value: NetworkRequest.grant_type)
        ]
        
        if let  clientID = NetworkRequest.clientID as?String{
            queryItems.append(   URLQueryItem(name: "client_id", value: clientID))
        }
        
        if let  clientSecret = NetworkRequest.clientSecret as?String{
            queryItems.append(   URLQueryItem(name: "client_secret", value:clientSecret))
        }
        
        return restClient.post(APIEndpoint.getToken, using:queryItems)
    }
    
    
    func getUserCoinbaseAccounts(limit: Int) -> AnyPublisher<CoinbaseUserAccountsResponse, Error> {
        restClient.get(APIEndpoint.userAccounts(limit))
    }
    
    
    func getCoinbaseUserAuthInformation() -> AnyPublisher<CoinbaseUserAuthInformation, Error> {
        restClient.get(APIEndpoint.userAuthInformation)
    }
    
    func getCoinbaseExchangeRates(currency: String) -> AnyPublisher<CoinbaseExchangeRateResponse, Error> {
        restClient.get(APIEndpoint.exchangeRates(currency))
    }
    
    func getCoinbaseActivePaymentMethods() -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.get(APIEndpoint.activePaymentMethods)
    }
    
    func placeCoinbaseBuyOrder(accountId: String, request: CoinbasePlaceBuyOrderRequest) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.post(APIEndpoint.placeBuyOrder(accountId), using: request, using: nil)
    }
    
    func commitCoinbaseBuyOrder(accountId: String, orderID: String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.post(APIEndpoint.commitBuyOrder(accountId,orderID), using: nil as String?, using: nil)
    }
    
    func sendCoinsToWallet(accountId: String, api2FATokenVersion: String, request: CoinbaseTransactionsRequest) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.post(APIEndpoint.sendCoinsToWallet(accountId), using: request, using: api2FATokenVersion)
    }
    
    func getBaseIdForUSDModel(baseCurrency: String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.get(APIEndpoint.getBaseIdForUSDModel(baseCurrency))
    }
    
    func swapTradeCoinbase(request: CoinbaseSwapeTradeRequest) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.post(APIEndpoint.swapTrade, using: request, using: nil)
    }
    
    func swapTradeCommitCoinbase(tradeId: String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.post(APIEndpoint.swapTradeCommit(tradeId), using: nil as String?, using: nil)
    }
    
    func getCoinbaseAccountAddress(accountId: String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.get(APIEndpoint.accountAddress(accountId))
    }
    
    func createCoinbaseAccountAddress(accountId: String, request: CoinbaseCreateAddressesRequest) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        restClient.post(APIEndpoint.createAccountAddress(accountId),using: request, using: nil)
    }
    
}

