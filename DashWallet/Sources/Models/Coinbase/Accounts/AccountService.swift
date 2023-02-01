//
//  Created by tkhp
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

import Foundation

// MARK: - AccountService

class AccountService {
    private let accountRepository: AccountRepository
    private weak var authInterop: CBAuthInterop?

    init(authInterop: CBAuthInterop) {
        self.authInterop = authInterop
        accountRepository = AccountRepository(authInterop: authInterop)
    }

    public func refreshAccount(_ accountName: String) async throws {
        let account = try await account(by: accountName)
        try await refresh(account: account)
    }

    public func refresh(account: CBAccount) async throws {
        try await account.refreshAccount()
        CBAccountManager.shared.store(account: account)
    }

    public func account(by name: String) async throws -> CBAccount {
        try await accountRepository.account(by: name)
    }

    public func allAccounts() async throws -> [CBAccount] {
        try await accountRepository.all()
    }

    public func retrieveAddress(for accountName: String) async throws -> String {
        let account = try await account(by: accountName)
        return try await account.retrieveAddress()
    }

    public func send(from accountName: String, amount: UInt64, verificationCode: String?) async throws -> CoinbaseTransaction {
        let account = try await account(by: accountName)

        let tx = try await account.send(amount: amount, verificationCode: verificationCode)
        return tx
    }

    public func placeBuyOrder(for accountName: String, amount: UInt64, paymentMethod: CoinbasePaymentMethod) async throws -> CoinbasePlaceBuyOrder {
        let account = try await account(by: accountName)
        return try await account.placeCoinbaseBuyOrder(amount: amount, paymentMethod: paymentMethod)
    }

    public func commitBuyOrder(accountName: String, orderID: String) async throws -> CoinbasePlaceBuyOrder {
        let account = try await account(by: accountName)

        let order = try await account.commitCoinbaseBuyOrder(orderID: orderID)
        return order
    }

    func placeTradeOrder(from origin: CBAccount, to destination: CBAccount, amount: String) async throws -> CoinbaseSwapeTrade {
        try await origin.convert(amount: amount, to: destination)
    }

    public func commitTradeOrder(origin: CBAccount, orderID: String) async throws -> CoinbaseSwapeTrade {
        let order = try await origin.commitTradeOrder(orderID: orderID)
        return order
    }

    func removeStoredAccount() {
        CBAccountManager.shared.removeAccount()
    }
}

extension AccountService {
    var dashAccount: CBAccount? {
        accountRepository.dashAccount
    }
}
