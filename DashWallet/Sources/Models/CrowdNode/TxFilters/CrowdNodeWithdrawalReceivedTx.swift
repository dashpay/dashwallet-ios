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

final class CrowdNodeWithdrawalReceivedTx: TransactionFilter {
    private var joinedFilters: [TransactionFilter] = []
    
    func matches(tx: DSTransaction) -> Bool {
        if joinedFilters.contains(where: { filter in !filter.matches(tx: tx) }) {
            return false
        }
        
        let fromAddress = CrowdNode.crowdNodeAddress
        
        for address in tx.inputAddresses {
            if address as? String == fromAddress {
                return tx.outputs.allSatisfy({ output in !isApiResponse(coin: output.amount) })
            }
        }
    
        return false
    }
    
    func and(txFilter: TransactionFilter) -> CrowdNodeWithdrawalReceivedTx {
        joinedFilters.append(txFilter)
        return self
    }
    
    private func isApiResponse(coin: UInt64) -> Bool {
        guard coin >= CrowdNode.apiOffset else { return false }
        let toCheck = coin - CrowdNode.apiOffset
        
        return (1...1024).contains(toCheck) || (toCheck <= ApiCode.maxCode().rawValue && isPowerOfTwo(coin))
    }
    
    private func isPowerOfTwo(_ number: UInt64) -> Bool {
        return number & (number - 1) == 0
    }
}
