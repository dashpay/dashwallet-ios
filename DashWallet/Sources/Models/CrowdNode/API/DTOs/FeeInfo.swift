//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

private let kDefaultAmount = 100.0
private let kTypeNormal = "Normal"

struct FeeInfo: Codable {
    static let empty = FeeInfo(feeLadder: [FeeLadder.empty])
    let feeLadder: [FeeLadder]
    
    enum CodingKeys: String, CodingKey {
        case feeLadder = "FeeLadder"
    }
    
    func getNormalFee() -> FeeLadder? {
        return feeLadder.first { $0.type == kTypeNormal }
    }
}

struct FeeLadder: Codable {
    let name: String
    let type: String
    let amount: Double
    let fee: Double
    
    static let empty = FeeLadder(
        name: "",
        type: kTypeNormal,
        amount: kDefaultAmount,
        fee: CrowdNode.defaultFee * 100
    )
}
