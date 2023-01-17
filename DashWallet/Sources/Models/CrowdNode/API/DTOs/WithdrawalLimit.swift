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

struct WithdrawalLimit: Codable {
    static let maxPerTxKey = "AmountApiWithdrawalMax"
    static let maxPer1hKey = "AmountApiWithdrawal1hMax"
    static let maxPer24hKey = "AmountApiWithdrawal24hMax"
    
    let key: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case value = "Value"
    }
}

enum WithdrawalLimitPeriod: Int {
    case perTransaction = 0
    case perHour = 1
    case perDay = 2
}
