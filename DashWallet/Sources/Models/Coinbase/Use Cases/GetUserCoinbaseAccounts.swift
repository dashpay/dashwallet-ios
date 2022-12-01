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

// MARK: - GetUserCoinbaseAccounts

class GetUserCoinbaseAccounts {
    @Injected private var remoteService: CoinbaseService

    var lastKnownBalance: String? {
        GetUserCoinbaseAccounts.lastKnownBalance
    }

    var hasLastKnownBalance: Bool {
        lastKnownBalance != nil
    }

    func invoke(limit: Int = 300) -> AnyPublisher<CoinbaseUserAccountData?, Error> {
        remoteService.getUserCoinbaseAccounts(limit: limit)
            .map { (response: BaseDataResponse<CoinbaseUserAccountData>) in
                let account = response.data
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
