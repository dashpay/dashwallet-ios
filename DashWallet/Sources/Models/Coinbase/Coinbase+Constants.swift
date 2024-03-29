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
    static let redirectUri = "authhub://oauth-callback"
    static let grantType = "authorization_code"
    static let responseType = "code"
    static let scope =
        "wallet:accounts:read,wallet:user:read,wallet:payment-methods:read,wallet:buys:read,wallet:buys:create,wallet:transactions:transfer,wallet:transactions:request,wallet:transactions:read,wallet:supported-assets:read,wallet:sells:create,wallet:sells:read,wallet:transactions:send,wallet:addresses:read,wallet:addresses:create,wallet:trades:create,wallet:accounts:create,wallet:deposits:create"
    static let defaultFiat = "USD"
    static let sendLimitCurrency = defaultFiat
    static let sendLimitAmount: Decimal = 1.0
    static let sendLimitPeriod = "month"
    static let account = "all"
    static let buyFee = 0.006
    static let dashUSDPair = "DASH-USD"
    static let transactionTypeBuy = "BUY"
    
    static let clientSecret: String = {
        if let path = Bundle.main.path(forResource: "Coinbase-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            return dict["CLIENT_SECRET"] as! String
        } else {
            return ""
        }
    }()
    
    static let clientID: String = {
        if let path = Bundle.main.path(forResource: "Coinbase-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] {
            return dict["CLIENT_ID"] as! String
        } else {
            return ""
        }
    }()
}

