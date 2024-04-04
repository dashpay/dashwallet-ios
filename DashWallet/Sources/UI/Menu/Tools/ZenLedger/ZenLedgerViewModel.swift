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

import Foundation

class ZenLedgerViewModel: ObservableObject {
    private let zenLedger = ZenLedger()
    private let account = DWEnvironment.sharedInstance().currentAccount
    
    var isSynced: Bool {
        SyncingActivityMonitor.shared.state == .syncDone
    }
    
    func export() async throws -> String? {
        let allTransaction = account.allTransactions
        var addresses: [String] = []

        if allTransaction.isEmpty {
            addresses.append(account.receiveAddress ?? "")
        } else {
            for tx in allTransaction {
                addresses.append(contentsOf:
                    tx.outputs.compactMap { $0.address }.filter { account.containsAddress($0) }
                )
            }
        }
        
        return try await zenLedger.createPortfolio(addresses: addresses)
    }
}
