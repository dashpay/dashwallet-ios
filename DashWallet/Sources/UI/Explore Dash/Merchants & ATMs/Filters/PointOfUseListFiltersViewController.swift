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

typealias Item = PointOfUseListFilters

class PointOfUseListFiltersViewController: UIViewController {
    enum Section: CaseIterable {
        case paymentType
        case sortBy
        case location
        case radius
        case locationService
        case resetFilters
    }
    
//    struct Item: Hashable {
//        var title: String
//        var action: String
//        var filterName: String
//
//        func hash(into hasher: inout Hasher) {
//            hasher.combine(title)
//        }
//    }
    
    private var dataSource: UITableViewDiffableDataSource<Section, Item>! = nil
    private var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>! = nil
    
    @IBOutlet var tableView: UITableView!
    
    @IBAction func cancelAction() {
        dismiss(animated: true)
    }
    
    @IBAction func applyAction() {
        dismiss(animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureHierarchy()
        configureDataSource()
        reloadDataSource()
    }
    
    class func controller() -> PointOfUseListFiltersViewController {
        let storyboard = UIStoryboard(name: "ExploreDash", bundle: nil)
        return storyboard.instantiateViewController(withIdentifier: "PointOfUseListFiltersViewController") as! PointOfUseListFiltersViewController
    }
}

extension PointOfUseListFiltersViewController {
    private func configureHierarchy() {
        title = NSLocalizedString("Filters", comment: "Explore Dash")
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationController?.navigationBar.standardAppearance = appearance
        
        view.backgroundColor = .dw_secondaryBackground()
    }
    
    private func configureDataSource() {
        self.dataSource = UITableViewDiffableDataSource
        <Section, Item>(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: Item) -> UITableViewCell? in
            
            guard let wSelf = self else { return UITableViewCell() }
            
            let section = wSelf.currentSnapshot.sectionIdentifiers[indexPath.section]
            
            return tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier, for: indexPath)
        }
    }
    
    func reloadDataSource() {
        currentSnapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        currentSnapshot.appendSections(Section.allCases)

        currentSnapshot.appendItems([.paymentTypeDash, .paymentTypeGiftCard], toSection: .paymentType)
        currentSnapshot.appendItems([.sortDistance, .sortAZ, .sortZA], toSection: .sortBy)
        currentSnapshot.appendItems([.location], toSection: .location)
        currentSnapshot.appendItems([.radius1, .radius5, .radius20, .radius50], toSection: .radius)
        currentSnapshot.appendItems([.locationService], toSection: .locationService)
        currentSnapshot.appendItems([.reset], toSection: .resetFilters)
        
        self.dataSource.apply(currentSnapshot, animatingDifferences: false)
        self.dataSource.defaultRowAnimation = .none
    }
}

class FilterItemSelectableCell: FilterItemCell {
    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var checkboxButton: UIButton!
}

class FilterItemCell: UITableViewCell {
    @IBOutlet var nameLabel: UILabel!
}
