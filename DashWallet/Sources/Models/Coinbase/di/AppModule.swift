//
//  AppModule.swift
//  Coinbase
//
//  Created by hadia on 28/05/2022.
//

import Foundation
import Resolver

extension Resolver: ResolverRegistering {
    public static func registerAllServices() {
        defaultScope = .graph
        registerSingletons()
        registerRemote()
        registerDomain()
    }

    // TODO: refactor this
    private static func registerSingletons() {
        register { RestClientImpl() as RestClient }.scope(.application)
    }

    private static func registerRemote() {
        register { CoinbaseServiceImpl() as CoinbaseService }
    }


    private static func registerDomain() {
        register { GetUserCoinbaseAccounts() }
        register { GetUserCoinbaseToken() }
        register { CreateCoinbaseDashAddress() }
        register { GetDashExchangeRate() }
        register { SendDashFromCoinbaseToDashWallet() }
    }
}
