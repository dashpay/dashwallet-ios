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

// MARK: - CBSecureTokenService

class CBSecureTokenService: Codable {
    private(set) var accessToken: String
    private(set) var refreshToken: String
    private(set) var accessTokenExpirationDate: Date

    private lazy var httpClient = HTTPClient<CoinbaseEndpoint>()

    init(accessToken: String, refreshToken: String, accessTokenExpirationDate: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpirationDate = accessTokenExpirationDate
    }

    var hasValidAccessToken: Bool {
        Date() < accessTokenExpirationDate
    }

    func fetchAccessToken(refreshing: Bool = false) async throws -> String {
        if !refreshing && hasValidAccessToken {
            return accessToken
        }

        let result: CoinbaseTokenResponse = try await httpClient.request(.refreshToken(refreshToken: refreshToken))
        accessToken = result.accessToken
        refreshToken = result.refreshToken
        accessTokenExpirationDate = result.expirationDate
        return result.accessToken
    }

    func revokeAccessToken() async throws {
        try await httpClient.request(.revokeToken(token: accessToken))
    }
}
