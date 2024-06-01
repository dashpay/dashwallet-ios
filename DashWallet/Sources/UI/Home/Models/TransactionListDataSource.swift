//
//  Created by tkhp
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

import UIKit

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

// MARK: - TransactionListDataSource

@objc(DWTransactionListDataSource)
final class TransactionListDataSource: NSObject, ObservableObject {
    @objc
    var items: [DSTransaction]
    
    var groupedItems: [DateKey: [TransactionListDataItem]] = [:]
    
    var registrationStatus: DWDPRegistrationStatus?
    
    @objc
    var retryDelegate: DWDPRegistrationErrorRetryDelegate?
    
    @objc
    var isEmpty: Bool {
        groupedItems.isEmpty
    }
    
    var showsRegistrationStatus: Bool {
        registrationStatus != nil
    }
    
    private let crowdNodeTxSet: FullCrowdNodeSignUpTxSet
    
    @objc
    init(transactions: [DSTransaction], registrationStatus: DWDPRegistrationStatus?) {
        items = transactions
        
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
            items.sort(by: { $0.date > $1.date })
        }

        groupedItems = Dictionary(
            grouping: items.sorted(by: { $0.date > $1.date }),
            by: { DateKey(key: DWDateFormatter.sharedInstance.dateOnly(from: $0.date), date: $0.date) }
        )
        
        self.crowdNodeTxSet = crowdNodeTxSet
        self.registrationStatus = registrationStatus
    }
}

extension FullCrowdNodeSignUpTxSet {
    var isComplete: Bool {
        transactions.count == 5
    }
}
