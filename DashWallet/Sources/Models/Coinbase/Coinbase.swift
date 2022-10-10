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
import Resolver
import Combine

class Coinbase {
    @Injected
    private var getUserCoinbaseAccounts: GetUserCoinbaseAccounts
    
    @Injected
    private var getUserCoinbaseToken: GetUserCoinbaseToken
    
    var isAuthorized: Bool { return getUserCoinbaseToken.isUserLoginedIn() }
    
    public static let shared: Coinbase = Coinbase()
}

extension Coinbase {
    var lastKnownBalance: String? {
        getUserCoinbaseAccounts.lastKnownBalance
    }
    
    var hasLastKnownBalance: Bool {
        return getUserCoinbaseAccounts.hasLastKnownBalance
    }
    
    public func authorize(with code: String) -> AnyPublisher<CoinbaseToken?, Error> {

        getUserCoinbaseToken.invoke(code: code)
    }
    
    public func fetchUser() -> AnyPublisher<CoinbaseUserAccountData?, Error> {
        return getUserCoinbaseAccounts.invoke()
    }
    
    public func signOut() {
        getUserCoinbaseToken.signOut()
    }
}
