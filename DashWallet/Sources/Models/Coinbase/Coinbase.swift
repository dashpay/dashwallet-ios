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

let kDashCurrency = "DASH"
var kCoinbaseContactURL = URL(string: "https://help.coinbase.com/en/contact-us")!

// MARK: - Coinbase

class Coinbase {
    enum Error: Swift.Error {
        case noActiveUser
        case failedToStartAuthSession
        case failedToAuth
    }

    private lazy var coinbaseService = CoinbaseService()

    public static let shared = Coinbase()
}

extension Coinbase {
    var isAuthorized: Bool { Coinbase.accessToken != nil }

    var lastKnownBalance: UInt64? {
        guard let balance = Coinbase.lastKnownBalance, let dashNumber = Decimal(string: balance) else {
            return nil
        }

        let duffsNumber = Decimal(DUFFS)
        let plainAmount = dashNumber * duffsNumber
        return NSDecimalNumber(decimal: plainAmount).uint64Value
    }
}

extension Coinbase {
    @MainActor  public func signIn(with presentationContext: ASWebAuthenticationPresentationContextProviding) async throws {
        let signInURL: URL! = coinbaseService.OAuth2URL
        let callbackURLScheme = Coinbase.callbackURLScheme

        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Swift.Error>) in
            let authenticationSession = ASWebAuthenticationSession(url: signInURL,
                                                                   callbackURLScheme: callbackURLScheme) { callbackURL, error in
                guard error == nil,
                      let callbackURL,
                      let queryItems = URLComponents(string: callbackURL.absoluteString)?.queryItems,
                      let code = queryItems.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: Coinbase.Error.failedToAuth)
                    return
                }

                continuation.resume(returning: code)
            }

            authenticationSession.presentationContextProvider = presentationContext
            authenticationSession.prefersEphemeralWebBrowserSession = true

            if !authenticationSession.start() {
                continuation.resume(throwing: Coinbase.Error.failedToStartAuthSession)
            }
        }

        let _ = try await authorize(with: code)
        let _ = try await fetchAccount()
    }

    public func authorize(with code: String) async throws -> CoinbaseToken {
        try await coinbaseService.authorize(code: code)
    }

    public func fetchAccount() async throws -> CoinbaseUserAccountData {
        try await coinbaseService.account()
    }

    public func createNewCoinbaseDashAddress() async throws -> String {
        guard let coinbaseUserAccountId = Coinbase.coinbaseUserAccountId else {
            fatalError("We need coinbaseUserAccountId here")
        }

        return try await coinbaseService.createCoinbaseAccountAddress(accountId: coinbaseUserAccountId)
    }

    public func getDashExchangeRate() async throws -> CoinbaseExchangeRate? {
        try await coinbaseService.getCoinbaseExchangeRates(currency: kDashCurrency)
    }

    public func transferFromCoinbaseToDashWallet(verificationCode: String?,
                                                 coinAmountInDash: String,
                                                 dashWalletAddress: String) async throws -> [CoinbaseTransaction] {
        try await coinbaseService.send(amount: coinAmountInDash, to: dashWalletAddress, verificationCode: verificationCode)
    }

    public func signOut() async throws {
        Coinbase.accessToken = nil
        Coinbase.refreshToken = nil
        Coinbase.coinbaseUserAccountId = nil
        Coinbase.lastKnownBalance = nil
        // TODO: call appropriate api endpoint
    }
}
