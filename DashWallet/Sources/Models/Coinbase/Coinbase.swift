//
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://opensource.org/licenses/MIT
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AuthenticationServices
import Combine
import Foundation
import Resolver

let kDashCurrency = "DASH"
var kCoinbaseContactURL: URL = { URL(string: "https://help.coinbase.com/en/contact-us")! }()

class Coinbase {
    @Injected
    private var getUserCoinbaseAccounts: GetUserCoinbaseAccounts

    @Injected
    private var createCoinbaseDashAddress: CreateCoinbaseDashAddress

    @Injected
    private var getExchangeRate: GetDashExchangeRate

    @Injected
    private var getUserCoinbaseToken: GetUserCoinbaseToken

    @Injected
    private var sendDashFromCoinbaseToDashWallet: SendDashFromCoinbaseToDashWallet

    var isAuthorized: Bool { return getUserCoinbaseToken.isUserLoginedIn() }

    private var cancelables = [AnyCancellable]()

    public static let shared: Coinbase = Coinbase()
}

extension Coinbase {
    var lastKnownBalance: String? {
        getUserCoinbaseAccounts.lastKnownBalance
    }

    var hasLastKnownBalance: Bool {
        return getUserCoinbaseAccounts.hasLastKnownBalance
    }

    public func signIn(with presentationContext: ASWebAuthenticationPresentationContextProviding, completion: @escaping ((Result<Bool, Error>) -> Void)) {
        // TODO: Refactor this method
        let path = APIEndpoint.signIn.path

        var queryItems = [
            URLQueryItem(name: "redirect_uri", value: NetworkRequest.redirect_uri),
            URLQueryItem(name: "response_type", value: NetworkRequest.response_type),
            URLQueryItem(name: "scope", value: NetworkRequest.scope),
            URLQueryItem(name: "meta[\("send_limit_amount")]", value: "\(NetworkRequest.send_limit_amount)"),
            URLQueryItem(name: "meta[\("send_limit_currency")]", value: NetworkRequest.send_limit_currency),
            URLQueryItem(name: "meta[\("send_limit_period")]", value: NetworkRequest.send_limit_period),
            URLQueryItem(name: "account", value: NetworkRequest.account),
        ]

        if let clientID = NetworkRequest.clientID as? String {
            queryItems.append(URLQueryItem(name: "client_id", value: clientID))
        }

        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = "coinbase.com"
        urlComponents.path = path
        urlComponents.queryItems = queryItems
        //

        guard let signInURL = urlComponents.url
        else {
            print("Could not create the sign in URL .")
            return
        }

        let callbackURLScheme = NetworkRequest.callbackURLScheme
        print(signInURL)

        let authenticationSession = ASWebAuthenticationSession(
            url: signInURL,
            callbackURLScheme: callbackURLScheme) { callbackURL, error in
                // 1
                guard error == nil,
                      let callbackURL = callbackURL,
                      let queryItems = URLComponents(string: callbackURL.absoluteString)?.queryItems,
                      let code = queryItems.first(where: { $0.name == "code" })?.value
                else {
                    completion(.failure(error!))
                    return
                }

                self.authorize(with: code)
                    .receive(on: DispatchQueue.main)
                    .sink(receiveCompletion: { completion in
                        print(completion)
                    }, receiveValue: { [weak self] _ in
                            self!.fetchUser()
                            .receive(on: DispatchQueue.main)
                            .sink(receiveCompletion: { [weak self] completion in
                                
                            }, receiveValue: { [weak self] response in
                                completion(.success(true))
                            })
                            .store(in: &self!.cancelables)
                        
                        
                    })
                    .store(in: &self.cancelables)
            }

        authenticationSession.presentationContextProvider = presentationContext
        authenticationSession.prefersEphemeralWebBrowserSession = true

        if !authenticationSession.start() {
            //TODO: throw an error
            print("Failed to start ASWebAuthenticationSession")
        }
    }

    public func authorize(with code: String) -> AnyPublisher<CoinbaseToken?, Error> {
        getUserCoinbaseToken.invoke(code: code)
    }

    public func fetchUser() -> AnyPublisher<CoinbaseUserAccountData?, Error> {
        return getUserCoinbaseAccounts.invoke()
    }

    public func createNewCoinbaseDashAddress() -> AnyPublisher<String?, Error> {
        if let coinbaseUserAccountId = NetworkRequest.coinbaseUserAccountId {
            return createCoinbaseDashAddress.invoke(accountId: coinbaseUserAccountId)
        }
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    public func getDashExchangeRate() -> AnyPublisher<CoinbaseExchangeRate?, Error> {
        return getExchangeRate.invoke()
    }

    public func transferFromCoinbaseToDashWallet(verificationCode: String?,
                                                coinAmountInDash: String,
                                                dashWalletAddress: String) -> AnyPublisher<CoinbaseTransaction?, Error> {
        if let coinbaseUserAccountId = NetworkRequest.coinbaseUserAccountId {
            return sendDashFromCoinbaseToDashWallet.invoke(accountId: coinbaseUserAccountId,
                                                           verificationCode: verificationCode,
                                                           request: CoinbaseTransactionsRequest(type: CoinbaseTransactionsRequest.TransactionsType.send,
                                                                                                to: dashWalletAddress,
                                                                                                amount: coinAmountInDash,
                                                                                                currency: kDashCurrency,
                                                                                                idem: UUID()))
        }
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    public func signOut() {
        getUserCoinbaseToken.signOut()
    }
}
