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


// MARK: - CNCreateAccountTxDetailsViewController

final class CNCreateAccountTxDetailsViewController: BaseTxDetailsViewController {
    enum Section: Int, CaseIterable {
        case header
        case details
        case txs
    }

    private let model: CNCreateAccountTxDetailsModel
    private var sections: [Section] = Section.allCases

    @objc
    convenience init(transactions: [DSTransaction]) {
        self.init(transactions: transactions.map { Transaction(transaction: $0) })
    }

    init(transactions: [Transaction]) {
        model = CNCreateAccountTxDetailsModel(transactions: transactions)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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
            cell.updateView(with: model)
            cell.selectionStyle = .none
            cell.backgroundColor = .clear
            cell.backgroundView?.backgroundColor = .clear

            return cell
        case .details:
            let cell = tableView.dequeueReusableCell(withIdentifier: CNCreateAccountTxDetailsInfoCell.reuseIdentifier, for: indexPath)
            cell.selectionStyle = .none
            return cell
        case .txs:
            let tx = model.transactions[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: CNCreateAccountTxDetailsTxItemCell.reuseIdentifier, for: indexPath) as! CNCreateAccountTxDetailsTxItemCell
            cell.update(with: tx)
            cell.selectionStyle = .none
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
            return model.transactions.count
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = sections[indexPath.section]

        switch section {
        case .txs:
            let tx = model.transactions[indexPath.row]
            let vc = TXDetailViewController(model: .init(transaction: tx))
            navigationController?.pushViewController(vc, animated: true)
        default:
            break
        }
    }
}
