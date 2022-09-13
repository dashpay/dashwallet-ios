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
        registerRepository()
        registerDomain()
    }
    
    private static func registerSingletons() {
        register { RestClientImpl() as RestClient }.scope(.application)
       // register { CoreDataManager() }.scope(.application)
    }
    
    private static func registerRemote() {
        register { CoinbaseServiceImpl() as CoinbaseService }
    }
    
    private static func registerRepository() {
        register { CoinbaseRepository() }
    }
    
    private static func registerDomain() {
        register { GetUserCoinbaseAccounts() }
        register { GetUserCoinbaseToken() }
//        register { GetCharacterDetail() }
//        register { GetFavorites() }
//        register { UpdateFavorite() }
//        register { DeleteFavorite() }
    }
    
}

