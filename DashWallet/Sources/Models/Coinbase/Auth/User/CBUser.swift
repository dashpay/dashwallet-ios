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

import Foundation

private let kAccountKey = "kAccountKey"
private let kPaymentMethodsKey = "kPaymentMethodsKey"

private let kTokenServiceKey = "kAccountKey"

// MARK: - CBUser + Equatable

extension CBUser: Equatable {
    static func == (lhs: CBUser, rhs: CBUser) -> Bool {
        lhs.account == rhs.account
    }
}

// MARK: - CBUser

class CBUser: Codable {
    public var paymentMethods: [CoinbasePaymentMethod]?

    private var account: CoinbaseUserAccountData?
    private var tokenService: CBSecureTokenService

    init(tokenService: CBSecureTokenService) {
        self.tokenService = tokenService
    }

    required init?(coder: NSCoder) {
        if let accountData = coder.decodeObject(forKey: kAccountKey) as? Data {
            account = try? JSONDecoder().decode(CoinbaseUserAccountData.self, from: accountData)
        }

        if let paymentMethodsData = coder.decodeObject(forKey: kPaymentMethodsKey) as? Data {
            paymentMethods = try? JSONDecoder().decode([CoinbasePaymentMethod].self, from: paymentMethodsData)
        }

        tokenService = coder.decodeObject(forKey: kTokenServiceKey) as! CBSecureTokenService
    }
}

extension CBUser {
    var accountId: String? {
        account?.id
    }

    var balance: UInt64? {
        account?.balance.plainAmount
    }

    var accessToken: String {
        tokenService.accessToken
    }

    var refreshToken: String {
        tokenService.refreshToken
    }

    func refreshAccount() async throws {
        try await fetchAccount()
        try await fetchPaymentMethods()
    }

    func refreshAccessToken() async throws {
        try await tokenService.fetchAccessToken(refreshing: true)
    }

    func revokeAccessToken() async throws {
        try await tokenService.revokeAccessToken()
    }

    public func fetchAccount() async throws -> CoinbaseUserAccountData {
        let result: BaseDataResponse<CoinbaseUserAccountData> = try await CoinbaseAPI.shared.request(.userAccount)
        let newAccount = result.data
        account = newAccount
        return newAccount
    }

    public func fetchPaymentMethods() async throws {
        let result: BaseDataCollectionResponse<CoinbasePaymentMethod> = try await CoinbaseAPI.shared.request(.activePaymentMethods)
        paymentMethods = result.data
    }
}
