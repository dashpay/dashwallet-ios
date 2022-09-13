//
//  GetUserCoinbaseToken.swift
//  Coinbase
//
//  Created by hadia on 20/06/2022.
//
import Foundation
import Combine
import Resolver
import AuthenticationServices


class GetUserCoinbaseToken : NSObject, ObservableObject{
    @Injected private var coinbaseRepository: CoinbaseRepository
   
    
    func invoke(code: String) -> AnyPublisher<CoinbaseToken?, Error> {
        coinbaseRepository.getToken(code: code)
            .map { (response: CoinbaseToken) in
                NetworkRequest.accessToken = response.accessToken
                NetworkRequest.refreshToken = response.refreshToken
               return response
        }.eraseToAnyPublisher()
    }
    
    func isUserLoginedIn()->Bool{
      return   ((NetworkRequest.accessToken?.isEmpty) == false)
    }
    
    func signOut(){
        NetworkRequest.accessToken = ""
        NetworkRequest.refreshToken = ""
        NetworkRequest.lastKnownBalance = ""
    }
}
