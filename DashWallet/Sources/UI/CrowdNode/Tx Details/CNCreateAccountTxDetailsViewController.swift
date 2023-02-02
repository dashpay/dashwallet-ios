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

// MARK: - HeaderData

private struct HeaderData: TxDetailHeaderCellDataProvider {
    var title: String { NSLocalizedString("CrowdNode Account", comment: "") }

    var fiatAmount: String { "0,18 US$" }

    var icon: UIImage { UIImage(named: "tx.item.cn.icon")! }

    var tintColor: UIColor { .dw_label() }

    func dashAmountString(with font: UIFont) -> NSAttributedString {
        NSAttributedString(string: "DASH 1.24")
    }
}

// MARK: - CNCreateAccountTxDetailsViewController

final class CNCreateAccountTxDetailsViewController: BaseTxDetailsViewController {
    enum Section: Int, CaseIterable {
        case header
        case details
        case txs
    }

    var sections: [Section] = Section.allCases

    override func configureHierarchy() {
        super.configureHierarchy()

        let item = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction))
        navigationItem.rightBarButtonItem = item

        tableView.registerClass(for: CNCreateAccountTxDetailsInfoCell.self)
        tableView.registerClass(for: CNCreateAccountTxDetailsTxItemCell.self)
        tableView.delegate = self
        tableView.dataSource = self
    }
}

// MARK: UITableViewDataSource

extension CNCreateAccountTxDetailsViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]

        switch section {
        case .header:
            let cell = tableView.dequeueReusableCell(withIdentifier: TxDetailHeaderCell.reuseIdentifier,
                                                     for: indexPath) as! TxDetailHeaderCell
            cell.updateView(with: HeaderData())
            cell.selectionStyle = .none
            cell.backgroundColor = .clear
            cell.backgroundView?.backgroundColor = .clear
            return cell
        case .details:
            return tableView.dequeueReusableCell(withIdentifier: CNCreateAccountTxDetailsInfoCell.reuseIdentifier, for: indexPath)
        case .txs:
            let tx = DWEnvironment.sharedInstance().currentAccount.allTransactions[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: CNCreateAccountTxDetailsTxItemCell.reuseIdentifier, for: indexPath) as! CNCreateAccountTxDetailsTxItemCell
            cell.update(with: tx, dataProvider: DWTransactionListDataProvider())
            return cell
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = sections[section]

        switch section {
        case .header, .details:
            return 1
        case .txs:
            return 5
        }
    }
}
