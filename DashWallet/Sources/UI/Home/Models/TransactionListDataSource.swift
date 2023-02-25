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

extension TransactionListDataItem {
    var date: Date {
        switch self {
        case .crowdnode(let txs):
            return txs.last!.date
        case .tx(let tx):
            return tx.date
        }
    }
}

// MARK: - TransactionListDataSource

@objc(DWTransactionListDataSource)
final class TransactionListDataSource: NSObject, UITableViewDataSource {
    @objc
    var items: [DSTransaction]

    var _items: [TransactionListDataItem] = []

    var registrationStatus: DWDPRegistrationStatus?

    @objc
    var retryDelegate: DWDPRegistrationErrorRetryDelegate?

    @objc
    var isEmpty: Bool {
        _items.isEmpty
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
                .sorted(by: { $0.date > $1.date })
                .map { Transaction(transaction: $0) }

            items.insert(.crowdnode(crowdNodeTxs), at: 0)
            items.sort(by: { $0.date > $1.date })
        }

        _items = items.sorted(by: { $0.date > $1.date })

        self.crowdNodeTxSet = crowdNodeTxSet
        self.registrationStatus = registrationStatus
    }

    @objc
    @available(*, deprecated, message: "We try to don't use DSTransaction in UI")
    func transactionForIndexPath(_ indexPath: IndexPath) -> DSTransaction? {
        let index: Int
        if showsRegistrationStatus {
            if indexPath.row == 0 {
                return nil
            }
            index = indexPath.row - 1
        } else {
            index = indexPath.row
        }

        let item = _items[index]

        switch item {
        case .tx(let tx):
            return tx.tx
        default:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let itemsCount = _items.count
        if showsRegistrationStatus {
            return 1 + itemsCount
        } else {
            return itemsCount
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if showsRegistrationStatus && indexPath.row == 0 {
            if registrationStatus!.failed {
                let cellID = DWDPRegistrationErrorTableViewCell.dw_reuseIdentifier
                let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath) as! DWDPRegistrationErrorTableViewCell
                cell.status = registrationStatus
                cell.delegate = retryDelegate
                return cell
            }
            if registrationStatus!.state == .done {
                let cellID = DWDPRegistrationDoneTableViewCell.dw_reuseIdentifier
                let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath) as! DWDPRegistrationDoneTableViewCell
                cell.status = registrationStatus
                return cell
            } else {
                let cellID = DWDPRegistrationStatusTableViewCell.dw_reuseIdentifier
                let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath) as! DWDPRegistrationStatusTableViewCell
                cell.status = registrationStatus
                return cell
            }
        } else {
            let tx = _items[indexPath.row]
            switch tx {
            case .crowdnode(let txs):
                let cellId = CNCreateAccountCell.dw_reuseIdentifier
                let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! CNCreateAccountCell
                cell.update(with: txs)
                return cell
            case .tx(let tx):
                let cellId = TxListTableViewCell.dw_reuseIdentifier
                let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! TxListTableViewCell
                cell.update(with: tx)
                return cell
            }
        }
    }
}

// MARK: - TransactionListDataItemType

@objc(DWTransactionListDataItemType)
enum TransactionListDataItemType: Int {
    case tx
    case crowdnode
}

extension TransactionListDataSource {
    @objc
    func itemType(by indexPath: NSIndexPath) -> TransactionListDataItemType {
        if case TransactionListDataItem.tx = _items[indexPath.row] {
            return .tx
        }

        return .crowdnode
    }

    @objc
    func crowdnodeTxs() -> [DSTransaction] {
        crowdNodeTxSet.transactions.values.sorted(by: { $0.date > $1.date })
    }
}

extension FullCrowdNodeSignUpTxSet {
    var isComplete: Bool {
        transactions.count == 5
    }
}
