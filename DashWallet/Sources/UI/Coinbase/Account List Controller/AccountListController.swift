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

import Combine
import UIKit

// MARK: - AccountListController

final class AccountListController: BaseViewController {
    public var selectHandler: ((CBAccount) -> Void)?

    @IBOutlet var tableView: UITableView!

    private var model: AccountListModel!
    private var selectedItem: CBAccount!

    private var searchController: UISearchController!
    private var searchResultsController: ResultsViewController!
    private var activityIndicatorView: UIActivityIndicatorView!

    internal var cancellables = Set<AnyCancellable>()

    @IBAction
    func closeAction() {
        dismiss(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureModel()
        configureHierarchy()
    }

    class func controller() -> AccountListController {
        vc(AccountListController.self, from: sb("Coinbase"))
    }
}

extension AccountListController {
    private func configureModel() {
        model = AccountListModel()
        model.$items
            .receive(on: DispatchQueue.main)
            .filter { !$0.isEmpty }
            .sink { [weak self] _ in
                self?.activityIndicatorView.removeFromSuperview()
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()
        title = NSLocalizedString("Select a coin", comment: "Coinbase")

        let barButton = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction))
        navigationItem.rightBarButtonItem = barButton;

        tableView.backgroundColor = .dw_secondaryBackground()
        tableView.rowHeight = 60
        tableView.layoutMargins = .init(top: 0.0, left: 15, bottom: 0.0, right: 0)
        tableView.separatorInset = tableView.layoutMargins

        searchResultsController = storyboard?
            .instantiateViewController(withIdentifier: "ResultsViewController") as? ResultsViewController
        searchResultsController.tableView.rowHeight = tableView.rowHeight
        searchResultsController.selectHandler = { [weak self] item in
            self?.select(item: item)
        }

        searchController = UISearchController(searchResultsController: searchResultsController)
        searchController.automaticallyShowsCancelButton = true
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.delegate = self

        activityIndicatorView = UIActivityIndicatorView(style: .medium)
        activityIndicatorView.color = .dw_label()
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.startAnimating()
        view.addSubview(activityIndicatorView)

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        definesPresentationContext = true

        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

// MARK: UITableViewDelegate, UITableViewDataSource

extension AccountListController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        model.items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = model.items[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: AccountCell.reuseIdentifier, for: indexPath) as! AccountCell
        cell.selectionStyle = .none
        cell.update(with: item)

        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let item = model.items[indexPath.row]
        cell.isSelected = item.info == selectedItem?.info
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = model.items[indexPath.row]
        select(item: item)
    }

    private func select(item: CBAccount) {
        selectedItem = item
        selectHandler?(item)
        tableView.reloadData()
    }
}

// MARK: UISearchControllerDelegate

extension AccountListController: UISearchControllerDelegate {
    func presentSearchController(_ searchController: UISearchController) { }

    func willPresentSearchController(_ searchController: UISearchController) { }

    func didPresentSearchController(_ searchController: UISearchController) { }

    func willDismissSearchController(_ searchController: UISearchController) { }

    func didDismissSearchController(_ searchController: UISearchController) { }
}

// MARK: UISearchBarDelegate

extension AccountListController: UISearchBarDelegate { }

// MARK: UISearchResultsUpdating

extension AccountListController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        var filtered = model.items

        let whitespaceCharacterSet = CharacterSet.whitespaces
        let strippedString = searchController.searchBar.text!.trimmingCharacters(in: whitespaceCharacterSet).lowercased()

        filtered = filtered.filter {
            $0.info.currency.name.lowercased().hasPrefix(strippedString.lowercased()) ||
                $0.info.currency.code.lowercased().hasPrefix(strippedString.lowercased())
        }

        if let resultsController = searchController.searchResultsController as? ResultsViewController {
            resultsController.result = filtered
            resultsController.tableView.reloadData()
        }
    }
}

// MARK: - ResultsViewController

final class ResultsViewController: UITableViewController {
    var result: [CBAccount] = []
    var selectHandler: ((CBAccount) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        result.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = result[indexPath.row]

        let cell = tableView.dequeueReusableCell(withIdentifier: AccountCell.reuseIdentifier, for: indexPath) as! AccountCell
        cell.update(with: item)
        cell.selectionStyle = .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = result[indexPath.row]
        selectHandler?(item)
    }
}


