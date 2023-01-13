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

class AccountRepository {
    private weak var authInterop: CBAuthInterop!
    private var accountManager: CBAccountManager { CBAccountManager.shared }

    private var cachedAccounts: [String: CBAccount] = [:]

    var dashAccount: CBAccount? {
        cachedAccounts[kDashAccount]
    }

    init(authInterop: CBAuthInterop) {
        self.authInterop = authInterop

        if let dashUser = accountManager.storedAccount(with: authInterop) {
            cachedAccounts[kDashAccount] = dashUser
        }
    }

    func account(by name: String) async throws -> CBAccount {
        guard let acc = cachedAccounts[name] else {
            let account = CBAccount(accountName: name, authInterop: authInterop)
            try await account.refreshAccount()
            if kDashAccount == name {
                accountManager.store(account: account)
            }
            cachedAccounts[name] = account
            return account
        }

        return acc
    }

    func store(account: CBAccount) {
        accountManager.store(account: account)
    }

    /// Fetch all accounts with positive balance
    ///
    /// - Returns: Array of `CBAccount`
    ///
    /// - Throws: `Coinbase.Error`
    ///
    /// - Note: Only crypto accounts
    ///
    func all() async throws -> [CBAccount] {
        var items: [CBAccount] = []
        items.reserveCapacity(300)

        var endpoint: CoinbaseEndpoint? = .accounts
        while endpoint != nil {
            let response: BasePaginationResponse<CoinbaseUserAccountData> = try await CoinbaseAPI.shared.request(endpoint!)
            items += response.data
                .filter { $0.currency.type == .crypto && $0.balance.amount.decimal()! > 0 }
                .map { .init(info: $0, authInterop: authInterop) }

            if let nextUri = response.pagination.nextURI {
                endpoint = .path(nextUri)
            } else {
                endpoint = nil
            }
        }

        return items
    }
}
