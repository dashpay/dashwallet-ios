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

public final class SpendableTransaction: TransactionFilter {
    private let transactionManager: DSTransactionManager
    private let txHashData: Data
    private let account = DWEnvironment.sharedInstance().currentAccount

    init(transactionManager: DSTransactionManager, txHashData: Data) {
        self.transactionManager = transactionManager
        self.txHashData = txHashData
    }

    func matches(tx: DSTransaction) -> Bool {
        let hashMatch = tx.txHashData == txHashData

        if hashMatch {
            let relayCount = transactionManager.relayCount(forTransaction: tx.txHash)
            DSLogger.log("CrowdNode: SpendableTransaction matched hash \(tx.txHashHexString); relayCount: \(relayCount)")

            return relayCount > 0
        }

        return false
    }
}
