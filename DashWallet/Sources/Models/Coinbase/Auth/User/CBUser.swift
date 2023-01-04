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
private let kAuthLimitsKey = "kAuthLimitsKey"
private let kTokenServiceKey = "kAccountKey"

// MARK: - CBUser + Equatable

extension CBUser: Equatable {
    static func == (lhs: CBUser, rhs: CBUser) -> Bool {
        lhs === rhs
    }
}

// MARK: - CBUser

class CBUser: Codable {
    private var tokenService: CBSecureTokenService
    private var authInfo: CoinbaseUserAuthData?

    init(tokenService: CBSecureTokenService) {
        self.tokenService = tokenService

        Task {
            try await refreshUser()
        }
    }
}

extension CBUser {
    var sendLimitCurrency: String {
        authInfo?.oauthMeta?.sendLimitCurrency ?? Coinbase.sendLimitCurrency
    }

    var sendLimit: Decimal {
        authInfo?.oauthMeta?.sendLimitAmount?.decimal() ?? Coinbase.sendLimitAmount
    }

    var accessToken: String {
        tokenService.accessToken
    }

    var refreshToken: String {
        tokenService.refreshToken
    }

    func refreshUser() async throws {
        try await fetchAuthInfo()
    }

    func refreshAccessToken() async throws {
        try await tokenService.refreshAccessToken()
    }

    func revokeAccessToken() async throws {
        try await tokenService.revokeAccessToken()
    }

    @discardableResult
    public func fetchAuthInfo() async throws -> CoinbaseUserAuthData {
        try await refreshAccessToken()

        let result: BaseDataResponse<CoinbaseUserAuthData> = try await CoinbaseAPI.shared.request(.userAuthInformation)
        let newAuthInfo = result.data
        authInfo = newAuthInfo
        return newAuthInfo
    }
}
