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

protocol TerritoriesListViewControllerDelegate: AnyObject {
    func didSelectTerritory(_ territory: Territory)
    func didSelectCurrentLocation()
}

class TerritoriesListViewController: UITableViewController {
    public var selectedTerritory: Territory?
    public weak var delegate: TerritoriesListViewControllerDelegate?
    
    private var searchController: UISearchController!
    private var searchResultsController: SelectLocationResultsViewController!
    
    private var model: TerritoriesListModel!
   
    public var territoriesDataSource: TerritoryDataSource? {
        didSet {
            model?.territoriesDataSource = territoriesDataSource
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureModel()
        configureHierarchy()
    }
    
    class func controller() -> TerritoriesListViewController {
        let storyboard = UIStoryboard(name: "ExploreDash", bundle: nil)
        return storyboard.instantiateViewController(withIdentifier: "SelectStateViewController") as! TerritoriesListViewController
    }
}

extension TerritoriesListViewController {
    private func configureModel() {
        model = TerritoriesListModel()
        model.territoriesDataSource = territoriesDataSource
        model.territoriesDidChange = { [weak self] in
            self?.tableView.reloadData()
        }
    }
    
    private func configureHierarchy() {
        title = NSLocalizedString("Location", comment: "Explore Dash/Merchants/Filters/Location")
        
        let standardAppearance = UINavigationBarAppearance()
        standardAppearance.configureWithOpaqueBackground()
        standardAppearance.backgroundColor = .systemBackground
        standardAppearance.shadowColor = nil
        standardAppearance.shadowImage = nil
        
        let compactAppearance = standardAppearance.copy()
        
        let navBar = self.navigationController!.navigationBar
        navBar.isTranslucent = true
        navBar.standardAppearance = standardAppearance
        navBar.scrollEdgeAppearance = standardAppearance
        navBar.compactAppearance = compactAppearance
        if #available(iOS 15.0, *) {
            navBar.compactScrollEdgeAppearance = compactAppearance
        }

        tableView.layoutMargins = .init(top: 0.0, left: 15, bottom: 0.0, right: 0)
        tableView.separatorInset = tableView.layoutMargins
        
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

extension TerritoriesListViewController {
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
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "CurrentLocationCell", for: indexPath)
            return cell
        default:
            let territory = model.territories[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: tableViewCellIdentifier, for: indexPath)
            var configuration =  cell.defaultContentConfiguration()
            configuration.text = territory
            cell.contentConfiguration = configuration
            
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case 0:
            cell.setSelected(selectedTerritory == nil, animated: false)
        default:
            let territory = model.territories[indexPath.row]
            cell.isSelected = territory == selectedTerritory
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case 0:
            selectedTerritory = nil
            delegate?.didSelectCurrentLocation()
        default:
            let territory = model.territories[indexPath.row]
            selectedTerritory = territory
            delegate?.didSelectTerritory(territory)
        }
        
        tableView.reloadData()
    }
}

extension TerritoriesListViewController: UISearchControllerDelegate {
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

extension TerritoriesListViewController: UISearchBarDelegate {
    
}

extension TerritoriesListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        var filtered: [Territory] = model.territories
        
        let whitespaceCharacterSet = CharacterSet.whitespaces
        let strippedString = searchController.searchBar.text!.trimmingCharacters(in: whitespaceCharacterSet).lowercased()
        
        filtered = filtered.filter { $0.lowercased().hasPrefix(strippedString) }
        
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
