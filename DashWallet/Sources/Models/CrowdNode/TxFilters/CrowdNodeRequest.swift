//
//  Created by Andrei Ashikhmin
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

public class CrowdNodeRequest: CoinsToAddressTxFilter {
    let requestCode: ApiCode

    init(requestCode: ApiCode) {
        self.requestCode = requestCode

        let address = CrowdNodeConstants.crowdNodeAddress
        let amount = CrowdNodeConstants.apiOffset + requestCode.rawValue
        super.init(coins: amount, address: address)
    }

    override func matches(tx: DSTransaction) -> Bool {
        return super.matches(tx: tx) && fromAddresses.count == 1
    }
}
