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

import Foundation

// MARK: - ExtendedPublicKeysViewController

@objc(DWExtendedPublicKeysViewController)
final class ExtendedPublicKeysViewController: BaseViewController, NavigationStackControllable {
    private let model: ExtendedPublicKeysModel

    private var tableView: UITableView!

    init() {
        model = ExtendedPublicKeysModel()

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
    }
}

// MARK: UITableViewDelegate, UITableViewDataSource

extension ExtendedPublicKeysViewController: UITableViewDelegate, UITableViewDataSource {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let cell = tableView.cellForRow(at: indexPath) as? DerivationPathKeysCell, !cell.item.value.isEmpty else {
            return
        }

        UIPasteboard.general.string = cell.item.value
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.derivationPaths.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let info = model.derivationPaths[indexPath.row]
        let item = info.item

        let cell = tableView.dequeueReusableCell(type: DerivationPathKeysCell.self, for: indexPath)
        cell.update(with: item)
        cell.separatorInset = .init(top: 0, left: 15, bottom: 0, right: 0)
        return cell
    }
}

extension ExtendedPublicKeysViewController {
    private func configureHierarchy() {
        title = NSLocalizedString("Extended Public Keys", comment: "")
        view.backgroundColor = .dw_secondaryBackground()

        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.registerClass(for: DerivationPathKeysCell.self)
        tableView.registerClassforHeaderFooterView(for: DerivationPathKeysHeaderView.self)
        tableView.preservesSuperviewLayoutMargins = true
        tableView.backgroundColor = .dw_secondaryBackground()
        tableView.estimatedRowHeight = UITableView.automaticDimension
        tableView.rowHeight = UITableView.automaticDimension
        tableView.translatesAutoresizingMaskIntoConstraints = false
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

// MARK: NavigationBarStyleable

extension ExtendedPublicKeysViewController: NavigationBarStyleable {
    var prefersLargeTitles: Bool { true }
    var largeTitleDisplayMode: UINavigationItem.LargeTitleDisplayMode { .always }
}
