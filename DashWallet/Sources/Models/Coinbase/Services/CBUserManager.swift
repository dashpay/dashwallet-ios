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

private let kKeychainUserAccessKey = "coinbaseUserAccessKey"
private let kStoredUserCoderKey = "kStoredUserCoderKey"

// MARK: - CBUserManager

class CBUserManager {
    var storedUser: CBUser? {
        var error: NSError?
        let data = getKeychainData(kKeychainUserAccessKey, &error)

        guard error == nil, !data.isEmpty else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(CBUser.self, from: data)
    }

    @discardableResult func removeUser() -> Bool {
        setKeychainData(nil, kKeychainUserAccessKey, false)
    }

    @discardableResult func store(user: CBUser) -> Bool {
        let encoder = JSONEncoder()
        let data = try? encoder.encode(user)

        let result = setKeychainData(data, kKeychainUserAccessKey, false)

        return result
    }
}
