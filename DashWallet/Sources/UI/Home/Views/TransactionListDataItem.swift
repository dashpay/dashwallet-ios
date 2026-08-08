//  
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

struct TransactionGroup: Identifiable {
    let id: String
    let date: Date
    var items: [TransactionListDataItem]
    
    init(id: String, date: Date, items: [TransactionListDataItem]) {
        self.id = id
        self.date = date
        self.items = items
    }
}

enum TransactionListDataItem {
    case tx(Transaction, TxRowMetadata?)
    case shieldedActivity(ShieldedActivityItem)
    case platformActivity(PlatformAddressActivityItem)
    case crowdnode(FullCrowdNodeSignUpTxSet)
    case coinjoin(CoinJoinMixingTxSet)
    case coinjoinWithdrawal(CoinJoinWithdrawalTxSet)
}

extension TransactionListDataItem: Identifiable {
    var id: String {
        switch self {
        case .crowdnode(_):
            return FullCrowdNodeSignUpTxSet.id
        case .coinjoin(let set):
            return set.id
        case .coinjoinWithdrawal(let set):
            return set.id
        case .tx(let tx, _):
            return tx.txHashHexString
        case .shieldedActivity(let item):
            return item.id
        case .platformActivity(let item):
            return item.id
        }
    }

    var date: Date {
        switch self {
        case .crowdnode(let set):
            return set.transactionMap.values.first!.date
        case .coinjoin(let set):
            return set.groupDay
        case .coinjoinWithdrawal(let set):
            return set.groupDay
        case .tx(let tx, _):
            return tx.date
        case .shieldedActivity(let item):
            return item.date
        case .platformActivity(let item):
            return item.date
        }
    }

    /// False only for restored shielded entries whose original date is
    /// not recoverable (SDK `createdAtMs == 0`); their `date` is the
    /// `.distantPast` sort sentinel and must not be rendered or used as
    /// a day-group key.
    var hasKnownDate: Bool {
        switch self {
        case .shieldedActivity(let item):
            return item.hasKnownDate
        default:
            return true
        }
    }
}
