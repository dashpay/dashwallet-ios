//  
//  Created by Andrei Ashikhmin
//  Copyright © 2023 Dash Core Group. All rights reserved.
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

struct CoinbaseDepositResponse: Codable {
    let id: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let resource: String
    let resourcePath: String
    let committed: Bool
    let payoutAt: String

    enum CodingKeys: String, CodingKey {
        case id, status, resource, committed
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case resourcePath = "resource_path"
        case payoutAt = "payout_at"
    }
}
