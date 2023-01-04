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

final class CrowdNodeDepositTx: TransactionFilter {
    private(set) final var accountAddress: String
    
    init(accountAddress: String) {
        self.accountAddress = accountAddress
    }
    
    func matches(tx: DSTransaction) -> Bool {
        let allFromAccount = tx.inputAddresses.allSatisfy { $0 as! String == accountAddress }
        guard allFromAccount else { return false }
        let crowdNodeAddress = CrowdNode.crowdNodeAddress
        
        for output in tx.outputs {
            if output.address == crowdNodeAddress {
                return !isApiRequest(coin: output.amount)
            }
        }
        
        return false
    }
    
    private func isApiRequest(coin: UInt64) -> Bool {
        let toCheck = coin - CrowdNode.apiOffset
        return toCheck <= ApiCode.maxCode().rawValue
    }
}
