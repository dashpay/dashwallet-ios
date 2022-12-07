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

    private var auth = CBAuth()
    private var tx = CBTransactions()

    public static let shared = Coinbase()

    init() {
        CoinbaseAPI.shared.secureTokenProvider = auth
    }
}

extension Coinbase {
    var isAuthorized: Bool { auth.currentUser != nil }

    var lastKnownBalance: UInt64? {
        guard let balance = auth.currentUser?.balance else {
            return nil
        }

        return balance
    }
}

extension Coinbase {
    @MainActor public func signIn(with presentationContext: ASWebAuthenticationPresentationContextProviding) async throws {
        try await auth.signIn(with: presentationContext)
    }

    public func createNewCoinbaseDashAddress() async throws -> String {
        guard let coinbaseUserAccountId = auth.currentUser?.accountId else {
            throw Coinbase.Error.noActiveUser
        }

        return try await coinbaseService.createCoinbaseAccountAddress(accountId: coinbaseUserAccountId)
    }

    public func getDashExchangeRate() async throws -> CoinbaseExchangeRate? {
        try await coinbaseService.getCoinbaseExchangeRates(currency: kDashCurrency)
    }

    public func transferFromCoinbaseToDashWallet(verificationCode: String?,
                                                 coinAmountInDash: String,
                                                 dashWalletAddress: String) async throws -> CoinbaseTransaction {
        guard let accountId = auth.currentUser?.accountId else {
            throw Coinbase.Error.noActiveUser
        }

        return try await tx.send(from: accountId, amount: coinAmountInDash, to: dashWalletAddress, verificationCode: verificationCode)
    }

    public func signOut() async throws {
        try await auth.signOut()
    }
}
