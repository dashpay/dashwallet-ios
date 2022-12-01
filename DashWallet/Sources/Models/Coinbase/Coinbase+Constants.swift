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

extension Coinbase {
    // MARK: API
    static let callbackURLScheme = "authhub"
    static let clientSecret = Bundle.main.infoDictionary?["CLIENT_SECRET"]
    static let redirectUri = "authhub://oauth-callback"
    static let clientID = Bundle.main.infoDictionary?["CLIENT_ID"]
    static let grantType = "authorization_code"
    static let responseType = "code"
    static let scope =
        "wallet:accounts:read,wallet:user:read,wallet:payment-methods:read,wallet:buys:read,wallet:buys:create,wallet:transactions:transfer,wallet:transactions:request,wallet:transactions:read,wallet:supported-assets:read,wallet:sells:create,wallet:sells:read,wallet:transactions:send,wallet:addresses:read,wallet:addresses:create"
    static let send_limit_currency = "USD"
    static let send_limit_amount = 1
    static let send_limit_period = "month"
    static let account = "all"
}

extension Coinbase {
    // MARK: Private Constants
    private static let accessTokenKey = "accessToken"
    private static let refreshTokenKey = "refreshToken"
    private static let coinbaseUserAccountIdKey = "coinbaseUserAccountId"
    private static let lastKnownBalanceKey = "lastKnownBalance"

    // MARK: Properties
    static var coinbaseUserAccountId: String? {
        get {
            UserDefaults.standard.string(forKey: coinbaseUserAccountIdKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: coinbaseUserAccountIdKey)
        }
    }

    // MARK: Properties
    static var accessToken: String? {
        get {
            UserDefaults.standard.string(forKey: accessTokenKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: accessTokenKey)
        }
    }

    static var refreshToken: String? {
        get {
            UserDefaults.standard.string(forKey: refreshTokenKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: refreshTokenKey)
        }
    }

    static var lastKnownBalance: String? {
        get {
            UserDefaults.standard.string(forKey: lastKnownBalanceKey)
        }
        set {
            UserDefaults.standard.setValue(newValue, forKey: lastKnownBalanceKey)
        }
    }
}
