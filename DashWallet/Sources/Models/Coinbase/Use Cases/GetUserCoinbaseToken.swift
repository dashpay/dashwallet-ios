//
//  GetUserCoinbaseToken.swift
//  Coinbase
//
//  Created by hadia on 20/06/2022.
//
import AuthenticationServices
import Combine
import Foundation
import Resolver

class GetUserCoinbaseToken: NSObject, ObservableObject {
    @Injected private var remoteService: CoinbaseService
    
    func invoke(code: String) -> AnyPublisher<CoinbaseToken?, Error> {
        remoteService.getToken(code: code)
            .map { (response: CoinbaseToken) in
                NetworkRequest.accessToken = response.accessToken
                NetworkRequest.refreshToken = response.refreshToken
                return response
            }.eraseToAnyPublisher()
    }

    func isUserLoginedIn() -> Bool {
        return NetworkRequest.accessToken != nil
    }

    func signOut() {
        NetworkRequest.accessToken = nil
        NetworkRequest.refreshToken = nil
        NetworkRequest.coinbaseUserAccountId = nil
    }
}
