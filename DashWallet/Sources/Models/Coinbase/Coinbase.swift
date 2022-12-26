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
let kCoinbaseContactURL = URL(string: "https://help.coinbase.com/en/contact-us")!
let kCoinbaseAddPaymentMethodsURL = URL(string: "https://www.coinbase.com/settings/linked-accounts")!
let kCoinbaseFeeInfoURL = URL(string: "https://help.coinbase.com/en/coinbase/trading-and-funding/pricing-and-fees/fees")!
let kMaxDashAmountToTransfer: UInt64 = kOneDash
let kMinUSDAmountOrder: Decimal = 1.99

// MARK: - Coinbase

class Coinbase {
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

    var paymentMethods: [CoinbasePaymentMethod] {
        guard let paymentMethods = auth.currentUser?.paymentMethods else {
            return []
        }

        return paymentMethods
    }

    var lastKnownBalance: UInt64? {
        guard let balance = auth.currentUser?.balance else {
            return nil
        }

        return balance
    }

    var sendLimit: Decimal {
        auth.currentUser?.sendLimit ?? Coinbase.sendLimitAmount
    }
}

extension Coinbase {
    @MainActor public func signIn(with presentationContext: ASWebAuthenticationPresentationContextProviding) async throws {
        try await auth.signIn(with: presentationContext)
    }

    public func createNewCoinbaseDashAddress() async throws -> String {
        guard let coinbaseUserAccountId = auth.currentUser?.accountId else {
            throw Coinbase.Error.general(.noActiveUser)
        }

        return try await coinbaseService.createCoinbaseAccountAddress(accountId: coinbaseUserAccountId)
    }

    public func getDashExchangeRate() async throws -> CoinbaseExchangeRate? {
        try await coinbaseService.getCoinbaseExchangeRates(currency: kDashCurrency)
    }

    public func transferFromCoinbaseToDashWallet(verificationCode: String?,
                                                 amount: UInt64) async throws -> CoinbaseTransaction {
        DSLogger.log("Tranfer from coinbase: transferFromCoinbaseToDashWallet")

        guard let accountId = auth.currentUser?.accountId else {
            throw Coinbase.Error.general(.noActiveUser)
        }

        // NOTE: Make sure we format the amount back into coinbase format (en_US)
        let amount = amount.formattedDashAmount.coinbaseAmount()

        let tx = try await tx.send(from: accountId, amount: amount, verificationCode: verificationCode)
        try? await auth.currentUser?.refreshAccount()
        return tx
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
    func placeCoinbaseBuyOrder(amount: UInt64, paymentMethod: CoinbasePaymentMethod) async throws -> CoinbasePlaceBuyOrder {
        guard let accountId = auth.currentUser?.accountId else {
            throw Coinbase.Error.general(.noActiveUser)
        }

        return try await tx.placeCoinbaseBuyOrder(accountId: accountId, amount: amount, paymentMethod: paymentMethod)
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
        guard let accountId = auth.currentUser?.accountId else {
            throw Coinbase.Error.general(.noActiveUser)
        }

        let order = try await tx.commitCoinbaseBuyOrder(accountId: accountId, orderID: orderID)
        return order
    }

    public func signOut() async throws {
        guard let _ = auth.currentUser?.accountId else {
            throw Coinbase.Error.general(.noActiveUser)
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
