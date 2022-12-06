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

class CBSecureTokenService {
    private(set) var accessToken: String
    private(set) var refreshToken: String
    private(set) var accessTokenExpirationDate: Date

    private lazy var httpClient = HTTPClient<CoinbaseAPI>()

    init(accessToken: String, refreshToken: String, accessTokenExpirationDate: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpirationDate = accessTokenExpirationDate
    }

    required init?(coder: NSCoder) {
        accessToken = coder.decodeObject(forKey: CBSecureTokenService.kAccessTokenKey) as! String
        refreshToken = coder.decodeObject(forKey: CBSecureTokenService.kRefreshTokenKey) as! String
        accessTokenExpirationDate = coder.decodeObject(forKey: CBSecureTokenService.kAccessTokenExpirationDate) as! Date
    }

    var hasValidAccessToken: Bool {
        Date() < accessTokenExpirationDate
    }

    func fetchAccessToken(refreshing: Bool = false) async throws -> String {
        let result: CoinbaseTokenResponse = try await httpClient.request(.refreshToken(refreshToken: refreshToken))
        accessToken = result.accessToken
        refreshToken = result.refreshToken
        accessTokenExpirationDate = result.expirationDate
        return result.accessToken
    }
}

// MARK: NSSecureCoding

extension CBSecureTokenService: NSSecureCoding {
    static let kAccessTokenKey = "kAccessTokenKey"
    static let kRefreshTokenKey = "kRefreshTokenKey"
    static let kAccessTokenExpirationDate = "kAccessTokenExpirationDate"

    static var supportsSecureCoding = true

    func encode(with coder: NSCoder) {
        coder.encode(accessToken, forKey: CBSecureTokenService.kAccessTokenKey)
        coder.encode(refreshToken, forKey: CBSecureTokenService.kRefreshTokenKey)
        coder.encode(accessTokenExpirationDate, forKey: CBSecureTokenService.kAccessTokenExpirationDate)
    }
}
