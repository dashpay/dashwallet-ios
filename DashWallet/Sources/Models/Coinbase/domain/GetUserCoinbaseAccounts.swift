//
//  GetUserCoinbaseAccounts.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Combine
import Foundation
import Resolver

private let lastKnownBalanceKey = "lastKnownBalance"

class GetUserCoinbaseAccounts {
    @Injected private var coinbaseRepository: CoinbaseRepository

    var lastKnownBalance: String? {
        GetUserCoinbaseAccounts.lastKnownBalance
    }

    var hasLastKnownBalance: Bool {
        return lastKnownBalance != nil
    }

    func invoke(limit: Int = 300) -> AnyPublisher<CoinbaseUserAccountData?, Error> {
        coinbaseRepository.getUserCoinbaseAccounts(limit: limit)
            .map { (response: CoinbaseUserAccountsResponse) in
                let account = response.data.first(where: { $0.currency.name == "Dash" })
                GetUserCoinbaseAccounts.lastKnownBalance = account?.balance.amount
                NetworkRequest.coinbaseUserAccountId = account?.id
                return account
            }.eraseToAnyPublisher()
    }

    func signOut() {
        GetUserCoinbaseAccounts.lastKnownBalance = nil
    }
}

extension GetUserCoinbaseAccounts {
    static var lastKnownBalance: String? {
        get {
            UserDefaults.standard.string(forKey: lastKnownBalanceKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: lastKnownBalanceKey)
        }
    }
}
