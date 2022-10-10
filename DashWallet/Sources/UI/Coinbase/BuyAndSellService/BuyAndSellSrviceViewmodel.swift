//
//  BuyAndSellSrviceViewmodel.swift
//  Coinbase
//
//  Created by hadia on 06/09/2022.
//
import Foundation
import Combine
import Resolver
import AuthenticationServices

class BuyAndSellSrviceViewmodel:NSObject,ObservableObject {
    
    @Published
    var accounts: [CoinbaseUserAccountData] = []
    
    private var cancelables = [AnyCancellable]()
    
    @Published
    var dashAccount: CoinbaseUserAccountData?
    
    @Published
    var isConnected: Bool = false
    
    @Published
    var buyAndSellDashServicesList = BuyAndSellDashServicesModel.getBuyAndSellDashServicesList
    
    @Published
    var showUserNeedDashWallet: Bool  = false
    
    private var coinbase: Coinbase = Coinbase.shared
    func getCoinbaseAccountFaitValue(balance: String)->String? {
        let priceManger = DSPriceManager.sharedInstance()
        let dashAmount = DWAmountObject(dashAmountString: balance,
                                        localFormatter: priceManger.localFormat,
                                        currencyCode: priceManger.localCurrencyCode)
        
        return priceManger.localCurrencyString(forDashAmount: dashAmount.plainAmount)
    }
    
    func checkServiceStatus(){
        isConnected = coinbase.isAuthorized
        if (isConnected){
            loadUserCoinbaseAccounts()
        }else{
            if let index = buyAndSellDashServicesList.firstIndex(where: {$0.serviceType == BuyAndSellDashServicesModel.ServiceType.COINBASE}) {
                buyAndSellDashServicesList[index].serviceStatus = BuyAndSellDashServicesModel.ServiceStatus.IDLE
            }
        }
    }
    
    func loadUserCoinbaseAccounts() {
        
        if let index = buyAndSellDashServicesList.firstIndex(where: {$0.serviceType == BuyAndSellDashServicesModel.ServiceType.COINBASE}) {

            if let dashAmount = coinbase.lastKnownBalance {
                buyAndSellDashServicesList[index].serviceStatus = BuyAndSellDashServicesModel.ServiceStatus.CONNECTED
                buyAndSellDashServicesList[index].balance = dashAmount
                buyAndSellDashServicesList[index].localBalance = getCoinbaseAccountFaitValue(balance: dashAmount)
            }
        }
        
        coinbase.fetchUser()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] response in
              
                if response == nil{
                    self?.showUserNeedDashWallet = true
                    self?.coinbase.signOut()
                    return
                }
                
                self?.dashAccount = response
                
                self?.isConnected = true
                
                if let index = self?.buyAndSellDashServicesList.firstIndex(where: {$0.serviceType == BuyAndSellDashServicesModel.ServiceType.COINBASE}) {
                    if let dashAmount  = self?.dashAccount?.balance.amount {
                        self?.buyAndSellDashServicesList[index].serviceStatus = BuyAndSellDashServicesModel.ServiceStatus.CONNECTED
                        self?.buyAndSellDashServicesList[index].balance =  dashAmount
                        self?.buyAndSellDashServicesList[index].localBalance =  self?.getCoinbaseAccountFaitValue(balance: dashAmount)
                        
                    }
                }
            })
            .store(in: &cancelables)
    }
    
    
    func signInTapped() {
        if (coinbase.isAuthorized && coinbase.hasLastKnownBalance){
            isConnected = true
            if let index = buyAndSellDashServicesList.firstIndex(where: {$0.serviceType == BuyAndSellDashServicesModel.ServiceType.COINBASE}) {
                buyAndSellDashServicesList[index].serviceStatus = BuyAndSellDashServicesModel.ServiceStatus.CONNECTED
            }
        } else{
            
            let path =  APIEndpoint.signIn.path
            
            var queryItems = [
                URLQueryItem(name: "redirect_uri", value: NetworkRequest.redirect_uri),
                URLQueryItem(name: "response_type", value: NetworkRequest.response_type),
                URLQueryItem(name: "scope", value: NetworkRequest.scope),
                URLQueryItem(name: "meta[\("send_limit_amount")]", value: "\(NetworkRequest.send_limit_amount)"),
                URLQueryItem(name: "meta[\("send_limit_currency")]", value: NetworkRequest.send_limit_currency),
                URLQueryItem(name: "meta[\("send_limit_period")]", value: NetworkRequest.send_limit_period),
                URLQueryItem(name: "account", value: NetworkRequest.account)
            ]
            
            if let  clientID = NetworkRequest.clientID as?String{
                queryItems.append(   URLQueryItem(name: "client_id", value: clientID))
            }
            
            
            var urlComponents = URLComponents()
            urlComponents.scheme = "https"
            urlComponents.host = "coinbase.com"
            urlComponents.path = path
            urlComponents.queryItems =  queryItems
            //
            
            guard let signInURL =  urlComponents.url
            else {
                print("Could not create the sign in URL .")
                return
            }
            
            let callbackURLScheme = NetworkRequest.callbackURLScheme
            print(signInURL)
            
            let authenticationSession = ASWebAuthenticationSession(
                url: signInURL,
                callbackURLScheme: callbackURLScheme ) { callbackURL, error in
                    // 1
                    guard
                        error == nil,
                        let callbackURL = callbackURL,
                        // 2
                        let queryItems = URLComponents(string: callbackURL.absoluteString)?.queryItems,
                        // 3
                        let code = queryItems.first(where: { $0.name == "code" })?.value
                            // 4
                    else {
                        // 5
                        print("An error occurred when attempting to sign in.")
                        return
                    }
                    self.loadUserCoinbaseTokens(code: code)
                    
                }
            
            authenticationSession.presentationContextProvider = self
            authenticationSession.prefersEphemeralWebBrowserSession = true
            
            if !authenticationSession.start() {
                print("Failed to start ASWebAuthenticationSession")
            }
        }
    }
    
    func loadUserCoinbaseTokens(code: String) {
        coinbase.authorize(with: code)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] response in
                if( response?.accessToken?.isEmpty==false){
                    self?.loadUserCoinbaseAccounts()
                }
            })
            .store(in: &cancelables)
        
    }
    
}

extension BuyAndSellSrviceViewmodel: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession)
    -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
        // Keep only active scenes, onscreen and visible to the user
            .filter { $0.activationState == .foregroundActive }
        // Keep only the first `UIWindowScene`
            .first(where: { $0 is UIWindowScene })
        // Get its associated windows
            .flatMap({ $0 as? UIWindowScene })?.windows
        // Finally, keep only the key window
            .first(where: \.isKeyWindow)
        
        return window ?? ASPresentationAnchor()
    }
    
}
