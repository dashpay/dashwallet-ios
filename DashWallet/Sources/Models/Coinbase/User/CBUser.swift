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
private let kTokenServiceKey = "kAccountKey"

// MARK: - CBUser

class CBUser {
    private var account: CoinbaseUserAccountData
    private var tokenService: CBSecureTokenService

    required init?(coder: NSCoder) {
        let accountData = coder.decodeObject(forKey: kAccountKey) as! Data
        account = try! JSONDecoder().decode(CoinbaseUserAccountData.self, from: accountData)
        tokenService = coder.decodeObject(forKey: kTokenServiceKey) as! CBSecureTokenService
    }
}

extension CBUser {
    var accountId: String {
        account.id
    }

    var accessToken: String {
        tokenService.accessToken
    }

    var refreshToken: String {
        tokenService.refreshToken
    }

    func refreshAccessToken() async throws {
        try await tokenService.fetchAccessToken(refreshing: true)
    }
}

// MARK: NSSecureCoding

extension CBUser: NSSecureCoding {
    static var supportsSecureCoding = true

    func encode(with coder: NSCoder) {
        let data = try! JSONEncoder().encode(account)
        coder.encode(data, forKey: kAccountKey)
        coder.encode(tokenService, forKey: kTokenServiceKey)
    }
}
