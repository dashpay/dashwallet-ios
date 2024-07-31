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

class HomeViewModel: ObservableObject {
    @Published var txItems: Array<(DateKey, [TransactionListDataItem])> = []
    @Published var hasNetwork: Bool = true
    private var model: SyncModel = SyncModelImpl()
    
    init() {
        model.networkStatusDidChange = { status in
            self.hasNetwork = status == .online
        }
        self.hasNetwork = model.networkStatus == .online
    }
    
    func updateItems(transactions: [DSTransaction]) {
        Task.detached {
            let crowdNodeTxSet = FullCrowdNodeSignUpTxSet()
            var items: [TransactionListDataItem] = transactions.compactMap {
                if crowdNodeTxSet.isComplete { return .tx(Transaction(transaction: $0)) }
                
                return crowdNodeTxSet.tryInclude(tx: $0) ? nil : .tx(Transaction(transaction: $0))
            }

            if !crowdNodeTxSet.transactions.isEmpty {
                let crowdNodeTxs: [Transaction] = crowdNodeTxSet.transactions.values
                    .sorted { $0.date > $1.date }
                    .map { Transaction(transaction: $0) }
                
                items.insert(.crowdnode(crowdNodeTxs), at: 0)
            }

            let groupedItems = Dictionary(
                grouping: items.sorted(by: { $0.date > $1.date }),
                by: { DateKey(key: DWDateFormatter.sharedInstance.dateOnly(from: $0.date), date: $0.date) }
            )
            
            let arary = groupedItems.sorted(by: { kv1, kv2 in
                kv1.key.date > kv2.key.date
            })

            DispatchQueue.main.async {
                self.txItems = arary
            }
        }
    }
}

// MARK: - TransactionListDataItem

enum TransactionListDataItem {
    case tx(Transaction)
    case crowdnode([Transaction])
}

extension TransactionListDataItem: Identifiable {
    var tx: Transaction {
        switch self {
        case .crowdnode(let txs):
            return txs.first!
        case .tx(let tx):
            return tx
        }
    }
    
    var id: String {
        switch self {
        case .crowdnode(let txs):
            return txs.first!.txHashHexString
        case .tx(let tx):
            return tx.txHashHexString
        }
    }
    
    var date: Date {
        switch self {
        case .crowdnode(let txs):
            return txs.last!.date
        case .tx(let tx):
            return tx.date
        }
    }
}

struct DateKey: Hashable {
    let key: String
    let date: Date
    
    static func == (lhs: DateKey, rhs: DateKey) -> Bool {
        return lhs.key == rhs.key
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }
}

extension FullCrowdNodeSignUpTxSet {
    var isComplete: Bool {
        transactions.count == 5
    }
}
