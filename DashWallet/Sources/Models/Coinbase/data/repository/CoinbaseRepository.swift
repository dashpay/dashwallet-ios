//
//  CoinBaseRepository.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Combine
import Foundation
import Resolver

let DASH_CURRENCY = "DASH"

class CoinbaseRepository {
    
    @Injected private var remoteService: CoinbaseService

    func getUserCoinbaseAccounts(limit: Int) -> AnyPublisher<CoinbaseUserAccountsResponse, Error> {
        remoteService.getUserCoinbaseAccounts(limit: limit)
    }

    func getToken(code: String) -> AnyPublisher<CoinbaseToken, Error> {
        remoteService.getToken(code: code)
    }

    func getCoinbaseAccountDashAddress(accountId: String) -> AnyPublisher<CoinbasePaymentMethodsResponse, Error> {
        remoteService.getCoinbaseAccountAddress(accountId: accountId)
    }

    func createCoinbaseDashAddress(accountId: String) -> AnyPublisher<CoinbaseCreateAddressesResponse, Error> {
        remoteService.createCoinbaseAccountAddress(accountId: accountId, request: CoinbaseCreateAddressesRequest(name: "New receive address"))
    }

    func getCoinbaseExchangeRates() -> AnyPublisher<CoinbaseExchangeRateResponse, Error> {
        remoteService.getCoinbaseExchangeRates(currency: DASH_CURRENCY)
    }

    func tansferFromCoinbaseToDashWallet(accountId: String, api2FATokenVersion: String, request: CoinbaseTransactionsRequest) -> AnyPublisher<CoinbaseTransactionsResponse, Error> {
        remoteService.sendCoinsToWallet(accountId: accountId, api2FATokenVersion: api2FATokenVersion, request: request)
    }
}
