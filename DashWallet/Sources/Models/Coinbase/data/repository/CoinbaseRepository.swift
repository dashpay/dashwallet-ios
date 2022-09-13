//
//  CoinBaseRepository.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation
import Combine
import Resolver

class CoinbaseRepository {
    @Injected private var remoteService: CoinbaseService

    func getUserCoinbaseAccounts(limit: Int) -> AnyPublisher<CoinbaseUserAccountsResponse, Error> {
        remoteService.getUserCoinbaseAccounts(limit: limit)
    }
    
    func getToken(code: String) -> AnyPublisher<CoinbaseToken, Error> {
        remoteService.getToken(code: code)
    }
}

