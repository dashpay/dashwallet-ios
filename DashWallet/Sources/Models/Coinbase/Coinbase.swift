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
let kDashAccount = "DASH"

let kCoinbaseContactURL = URL(string: "https://help.coinbase.com/en/contact-us")!
let kCoinbaseAddPaymentMethodsURL = URL(string: "https://www.coinbase.com/settings/linked-accounts")!
let kCoinbaseFeeInfoURL = URL(string: "https://help.coinbase.com/en/coinbase/trading-and-funding/pricing-and-fees/fees")!
let kMaxDashAmountToTransfer: UInt64 = kOneDash
let kMinUSDAmountOrder: Decimal = 1.99
let kMinDashAmountToTransfer: UInt64 = 10_000

// MARK: - Coinbase

class Coinbase {
    private lazy var coinbaseService = CoinbaseService()

    private var auth: CBAuth!
    private var accountService: AccountService!
    private var paymentMethodsService: PaymentMethods!

    public static let shared = Coinbase()

    init() {
        CoinbaseAPI.initialize(with: self)

        auth = CBAuth()
        accountService = AccountService(authInterop: auth)
        paymentMethodsService = PaymentMethods(authInterop: auth)

        // Pre-fetch data
        Task {
            try await accountService.refreshAccount(kDashAccount)
            try await paymentMethodsService.fetchPaymentMethods()
        }
    }
}

extension Coinbase {
    var isAuthorized: Bool { auth.currentUser != nil }

    var paymentMethods: [CoinbasePaymentMethod] {
        get async throws {
            try await paymentMethodsService.fetchPaymentMethods()
        }
    }

    var lastKnownBalance: UInt64? {
        accountService.dashAccount?.balance
    }

    var sendLimit: Decimal {
        auth.currentUser?.sendLimit ?? Coinbase.sendLimitAmount
    }
}

extension Coinbase {
    @MainActor
    public func signIn(with presentationContext: ASWebAuthenticationPresentationContextProviding) async throws {
        try await auth.signIn(with: presentationContext)
        try await accountService.refreshAccount(kDashAccount)
    }

    public func createNewCoinbaseDashAddress() async throws -> String {
        do {
            return try await accountService.retrieveAddress(for: kDashAccount)
        } catch Coinbase.Error.userSessionRevoked {
            try await auth.signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    public func getDashExchangeRate() async throws -> CoinbaseExchangeRate? {
        do {
            return try await coinbaseService.getCoinbaseExchangeRates(currency: kDashCurrency)
        } catch Coinbase.Error.userSessionRevoked {
            try await auth.signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    public func transferFromCoinbaseToDashWallet(verificationCode: String?,
                                                 amount: UInt64) async throws -> CoinbaseTransaction {
        do {
            return try await accountService.send(from: kDashAccount, amount: amount, verificationCode: verificationCode)
        } catch Coinbase.Error.userSessionRevoked {
            try await auth.signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    /// Place Buy Order
    ///
    /// - Parameters:
    ///   - amount: Plain amount in Dash
    ///
    /// - Returns: CoinbasePlaceBuyOrder
    ///
    /// - Throws: Coinbase.Error
    ///
    func placeCoinbaseBuyOrder(amount: UInt64,
                               paymentMethod: CoinbasePaymentMethod) async throws -> CoinbasePlaceBuyOrder {
        do {
            return try await accountService.placeBuyOrder(for: kDashAccount, amount: amount, paymentMethod: paymentMethod)
        } catch Coinbase.Error.userSessionRevoked {
            try await auth.signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    /// Commit Buy Order
    ///
    /// - Parameters:
    ///   - orderID: Order id from `CoinbasePlaceBuyOrder` you receive by calling `placeCoinbaseBuyOrder`
    ///
    /// - Returns: CoinbasePlaceBuyOrder
    ///
    /// - Throws: Coinbase.Error
    ///
    func commitCoinbaseBuyOrder(orderID: String) async throws -> CoinbasePlaceBuyOrder {
        do {
            return try await accountService.commitBuyOrder(accountName: kDashAccount, orderID: orderID)
        } catch Coinbase.Error.userSessionRevoked {
            try await auth.signOut()
            throw Coinbase.Error.userSessionRevoked
        } catch {
            throw error
        }
    }

    public func signOut() async throws {
        guard isAuthorized else {
            return
        }

        try await auth.signOut()
    }

    public func addUserDidChangeListener(_ listener: @escaping UserDidChangeListenerBlock) -> UserDidChangeListenerHandle {
        auth.addUserDidChangeListener(listener)
    }

    public func removeUserDidChangeListener(handle: UserDidChangeListenerHandle) {
        auth.removeUserDidChangeListener(handle: handle)
    }
}

extension String {
    func coinbaseAmount() -> String {
        let locale = Locale(identifier: "en_US")

        guard locale.decimalSeparator != Locale.current.decimalSeparator else {
            return self
        }

        return localizedAmount(locale: locale)
    }
}

// MARK: - Coinbase + CoinbaseAPIAccessTokenProvider

extension Coinbase: CoinbaseAPIAccessTokenProvider {
    var accessToken: String? {
        auth.accessToken
    }

    func refreshTokenIfNeeded() async throws {
        try await auth.refreshTokenIfNeeded()
    }
}

