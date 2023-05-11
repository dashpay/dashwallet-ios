//
//  Created by PT
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

// MARK: - KeysOverviewViewController

@objc(DWKeysOverviewViewController)
final class KeysOverviewViewController: BaseViewController {
    private var tableView: UITableView!
    private var model: WalletKeysOverviewModel!

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureModel()
        configureHierarchy()
    }
}

extension KeysOverviewViewController {
    private func configureModel() {
        model = WalletKeysOverviewModel()
    }

    private func configureHierarchy() {
        title = NSLocalizedString("Masternode Keys", comment: "")
        view.backgroundColor = .dw_secondaryBackground()

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.preservesSuperviewLayoutMargins = true
        tableView.rowHeight = 62
        tableView.backgroundColor = .clear
        tableView.estimatedRowHeight = 62
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.registerClass(for: KeysOverviewCell.self)
        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor, constant: 0),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 0),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: 0),
        ])
    }
}

// MARK: UITableViewDataSource, UITableViewDelegate

extension KeysOverviewViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = model.items[indexPath.row]
        let count = model.keyCount(for: item)
        let used = model.usedCount(for: item)

        let cell = tableView.dequeueReusableCell(type: KeysOverviewCell.self, for: indexPath)
        cell.accessoryType = .disclosureIndicator
        cell.update(with: item, count: count, used: used)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let showVcBlock = { [weak self] in
            guard let self else { return }

            let item = model.items[indexPath.row]
            let derivationPath = model.derivationPath(for: item)
            let vc = DerivationPathKeysViewController(with: item, derivationPath: derivationPath)
            vc.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(vc, animated: true)
        }

        if DSAuthenticationManager.sharedInstance().didAuthenticate {
            showVcBlock()
        }
        else {
            DSAuthenticationManager.sharedInstance().authenticate(withPrompt: nil, usingBiometricAuthentication: false, alertIfLockout: true) { authenticatedOrSuccess, _, _ in

                guard authenticatedOrSuccess else { return }
                showVcBlock()
            }
        }
    }
}

// MARK: NavigationBarStyleable

extension KeysOverviewViewController: NavigationBarStyleable {
    var prefersLargeTitles: Bool { true }
    var largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode { .always }
}
