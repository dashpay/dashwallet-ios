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

// MARK: - CrowdNodeAPIConfirmationTx

final class CrowdNodeAPIConfirmationTx: CoinsToAddressTxFilter {
    private var primaryAddress: String!

    init(primaryAddress: String, apiAddress: String, requireChainAccepted: Bool = false) {
        super.init(coins: CrowdNode.apiConfirmationDashAmount, address: apiAddress,
                   requireChainAccepted: requireChainAccepted)
        self.primaryAddress = primaryAddress
    }

    override func matches(_ tx: ObservedTransaction) -> Bool {
        super.matches(tx) && fromAddresses.contains(primaryAddress)
    }
}

// MARK: - CrowdNodeAPIConfirmationTxForwarded

final class CrowdNodeAPIConfirmationTxForwarded: CoinsToAddressTxFilter {
    init() {
        super.init(coins: CrowdNode.apiConfirmationDashAmount, address: CrowdNode.crowdNodeAddress, withFee: true)
    }
}
