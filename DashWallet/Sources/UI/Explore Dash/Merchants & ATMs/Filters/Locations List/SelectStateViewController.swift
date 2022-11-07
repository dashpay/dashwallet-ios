//  
//  Created by tkhp
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

private let tableViewCellIdentifier = "TerritoryCell"

class SelectStateViewController: UITableViewController {
    private var searchController: UISearchController!
    private var searchResultsController: SelectLocationResultsViewController!
    
    private var model: TerritoriesListModel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureModel()
        configureHierarchy()
    }
    
    class func controller() -> SelectStateViewController {
        let storyboard = UIStoryboard(name: "ExploreDash", bundle: nil)
        return storyboard.instantiateViewController(withIdentifier: "SelectStateViewController") as! SelectStateViewController
    }
}

extension SelectStateViewController {
    private func configureModel() {
        model = TerritoriesListModel()
    }
    
    private func configureHierarchy() {
        title = NSLocalizedString("Location", comment: "Explore Dash/Merchants/Filters/Location")
        
        searchResultsController = self.storyboard?.instantiateViewController(withIdentifier: "SelectLocationResultsViewController") as? SelectLocationResultsViewController
        searchResultsController.tableView.delegate = self
        
        searchController = UISearchController(searchResultsController: searchResultsController)
        searchController.automaticallyShowsCancelButton = true
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.delegate = self
        
        navigationItem.searchController = searchController
        
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }
}

extension SelectStateViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        default:
            return model.territories.count
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: tableViewCellIdentifier, for: indexPath)
        var configuration =  cell.defaultContentConfiguration()
        configuration.text = model.territories[indexPath.row]
        cell.contentConfiguration = configuration
        return cell
    }
}

extension SelectStateViewController: UISearchControllerDelegate {
    func presentSearchController(_ searchController: UISearchController) {
    }
    
    func willPresentSearchController(_ searchController: UISearchController) {
    }
    
    func didPresentSearchController(_ searchController: UISearchController) {
    }
    
    func willDismissSearchController(_ searchController: UISearchController) {
    }
    
    func didDismissSearchController(_ searchController: UISearchController) {
    }
}

extension SelectStateViewController: UISearchBarDelegate {
    
}

extension SelectStateViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        var filtered: [Territory] = model.territories
        
        let whitespaceCharacterSet = CharacterSet.whitespaces
        let strippedString = searchController.searchBar.text!.trimmingCharacters(in: whitespaceCharacterSet).lowercased()
        
        filtered = filtered.filter { $0.lowercased().contains(strippedString) }
        
        if let resultsController = searchController.searchResultsController as? SelectLocationResultsViewController {
            resultsController.result = filtered
            resultsController.tableView.reloadData()
        }
    }
}

class SelectLocationResultsViewController: UITableViewController {
    var result: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return result.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let product = result[indexPath.row]
        
        let cell = tableView.dequeueReusableCell(withIdentifier: tableViewCellIdentifier, for: indexPath)
        var configuration =  cell.defaultContentConfiguration()
        configuration.text = product
        cell.contentConfiguration = configuration
        return cell
    }
}
