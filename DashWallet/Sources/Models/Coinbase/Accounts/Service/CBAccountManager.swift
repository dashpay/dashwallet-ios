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

private let kUserDefaultAccountAccessKey = "coinbaseAccountKey"

// MARK: - CBAccountManager

class CBAccountManager {

    func storedAccount(with authInterop: CBAuthInterop) -> CBAccount? {
        guard let data = UserDefaults.standard.data(forKey: kUserDefaultAccountAccessKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let accountInfo = try? decoder.decode(CoinbaseUserAccountData.self, from: data) else {
            return nil
        }

        return CBAccount(accountName: kDashAccount, info: accountInfo, authInterop: authInterop)
    }

    func removeAccount() {
        UserDefaults.standard.removeObject(forKey: kUserDefaultAccountAccessKey)
    }

    @discardableResult
    func store(account: CBAccount) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(account.info) else {
            return false
        }

        UserDefaults.standard.set(data, forKey: kUserDefaultAccountAccessKey)
        return true
    }

    static let shared = CBAccountManager()
}

