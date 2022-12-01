//
//  GetUserCoinbaseToken.swift
//  Coinbase
//
//  Created by hadia on 20/06/2022.
//
import AuthenticationServices
import Combine
import Foundation

class GetUserCoinbaseToken: NSObject, ObservableObject {
    private var remoteService: CoinbaseService = CoinbaseServiceImpl()

    func invoke(code: String) -> AnyPublisher<CoinbaseToken?, Error> {
        remoteService.getToken(code: code)
            .map { (response: CoinbaseToken) in
                NetworkRequest.accessToken = response.accessToken
                NetworkRequest.refreshToken = response.refreshToken
                return response
            }.eraseToAnyPublisher()
    }

    func isUserLoginedIn() -> Bool {
        NetworkRequest.accessToken != nil
    }

    func signOut() {
        NetworkRequest.accessToken = nil
        NetworkRequest.refreshToken = nil
        NetworkRequest.coinbaseUserAccountId = nil
    }
}
