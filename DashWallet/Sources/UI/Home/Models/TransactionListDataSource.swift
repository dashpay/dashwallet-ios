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

@objc(DWTransactionListDataSource)
final class TransactionListDataSource: NSObject, UITableViewDataSource {
    weak var dataProvider: DWTransactionListDataProviderProtocol!

    @objc
    var items: [DSTransaction]

    var registrationStatus: DWDPRegistrationStatus?

    @objc
    var retryDelegate: DWDPRegistrationErrorRetryDelegate?

    @objc
    var isEmpty: Bool {
        items.isEmpty
    }

    var showsRegistrationStatus: Bool {
        registrationStatus != nil
    }

    @objc
    init(transactions: [DSTransaction], registrationStatus: DWDPRegistrationStatus?, dataProvider: DWTransactionListDataProviderProtocol) {
        items = transactions
        self.registrationStatus = registrationStatus
        self.dataProvider = dataProvider
    }

    @objc
    func transactionForIndexPath(_ indexPath: IndexPath) -> DSTransaction? {
        let index: Int
        if showsRegistrationStatus {
            if indexPath.row == 0 {
                return nil
            }
            index = indexPath.row - 1
        } else {
            index = indexPath.row - 1
        }
        return items[index]
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let itemsCount = items.count
        if showsRegistrationStatus {
            return 1 + itemsCount
        } else {
            return 1 + itemsCount
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
            if indexPath.row == 0 {
                let cellId = CNCreateAccountCell.dw_reuseIdentifier
                let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! CNCreateAccountCell
                return cell
            }
            let tx = transactionForIndexPath(indexPath)!
            let cellId = TxListTableViewCell.dw_reuseIdentifier
            let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! TxListTableViewCell
            cell.update(with: tx, dataProvider: dataProvider!)
            return cell
        }
    }
}
