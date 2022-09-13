//
//  CoinbaseAccountViewmodel.swift
//  Coinbase
//
//  Created by hadia on 31/05/2022.
//

import Foundation
import Combine
import Resolver
import AuthenticationServices

class CoinbaseAccountViewmodel: NSObject,ObservableObject {
    @Injected
    private var getUserCoinbaseAccounts: GetUserCoinbaseAccounts
    
    @Injected
    private var getUserCoinbaseToken: GetUserCoinbaseToken
    
    @Published
    var accounts: [CoinbaseUserAccountData] = []
    
    private var cancelables = [AnyCancellable]()
    
    @Published
    var dashAccount: CoinbaseUserAccountData?
    
    @Published
    var isConnected: Bool = false
    
    func loadUserCoinbaseAccounts() {
        isConnected = getUserCoinbaseToken.isUserLoginedIn()
        getUserCoinbaseAccounts.invoke()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] response in
                self?.dashAccount = response
            })
            .store(in: &cancelables)
    }
    
    func signOutTapped(){
        getUserCoinbaseToken.signOut()
        isConnected = getUserCoinbaseToken.isUserLoginedIn()
    }
    
    
    func loadUserCoinbaseTokens(code: String) {
        getUserCoinbaseToken.invoke(code: code)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] response in
                if( response?.accessToken?.isEmpty==false){
                    self?.isConnected = true
                    self?.loadUserCoinbaseAccounts()
                }
            })
            .store(in: &cancelables)
        
    }
    
    func getCoinbaseAccountFaitValue(balance: String)->String? {
        let priceManger = DSPriceManager.sharedInstance()
        let dashAmount = DWAmountObject(dashAmountString: balance,
                                        localFormatter: priceManger.localFormat,
                                        currencyCode: priceManger.localCurrencyCode)
        
        return priceManger.localCurrencyString(forDashAmount: dashAmount.plainAmount)
    }
    
    func getLastKnownBalance()->String?{
        if(getUserCoinbaseAccounts.isUserHasLastKnownBalance()){
            if let dashAmount  = getUserCoinbaseAccounts.getLastKnownBalance() {
               return dashAmount
            }
        }
        return nil
    }
    
}
