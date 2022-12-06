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

// MARK: - CBAuthCredential

class CBAuthCredential {
    let accessToken: String

    init(accessToken: String) {
        self.accessToken = accessToken
    }

    required init?(coder: NSCoder) {
        accessToken = coder.decodeObject(forKey: CBAuthCredential.kAccessTokenKey) as! String
    }
}

// MARK: NSSecureCoding

extension CBAuthCredential: NSSecureCoding {
    static let kAccessTokenKey = "kAccessTokenKey"

    static var supportsSecureCoding = true

    func encode(with coder: NSCoder) {
        coder.encode(accessToken, forKey: CBAuthCredential.kAccessTokenKey)
    }
}
