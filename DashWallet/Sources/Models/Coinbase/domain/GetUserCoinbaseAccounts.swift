//
//  GetUserCoinbaseAccounts.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation
import Combine
import Resolver


class GetUserCoinbaseAccounts{
    @Injected private var coinbaseRepository: CoinbaseRepository
    
    func invoke(limit: Int =  300) -> AnyPublisher<CoinbaseUserAccountData?, Error> {
        coinbaseRepository.getUserCoinbaseAccounts(limit: limit)
            .map { (response: CoinbaseUserAccountsResponse) in
                let account = response.data.first(where: {$0.currency.name == "Dash"})
                NetworkRequest.lastKnownBalance = account?.balance.amount
                return account
        }.eraseToAnyPublisher()
    }
    
    func getLastKnownBalance()->String?{
      return  NetworkRequest.lastKnownBalance
    }
    
    func isUserHasLastKnownBalance()->Bool{
      return   ((NetworkRequest.lastKnownBalance?.isEmpty) == false)
    }
}
