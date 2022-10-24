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

    
    @Published
    var accounts: [CoinbaseUserAccountData] = []
    
    private var cancelables = [AnyCancellable]()
    
    @Published
    var dashAccount: CoinbaseUserAccountData?
    
    @Published
    var isConnected: Bool = false
    
    private var coinbase: Coinbase = Coinbase.shared
    
    func loadUserCoinbaseAccounts() {
        isConnected = coinbase.isAuthorized
        coinbase.fetchUser()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] response in
                self?.dashAccount = response
            })
            .store(in: &cancelables)
    }
    
    func signOutTapped(){
        coinbase.signOut()
        isConnected = false
    }
    
    
    func loadUserCoinbaseTokens(code: String) {
        coinbase.authorize(with: code)
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
    
    func getLastKnownBalance()->String? {
        return coinbase.lastKnownBalance
    }
    
}
