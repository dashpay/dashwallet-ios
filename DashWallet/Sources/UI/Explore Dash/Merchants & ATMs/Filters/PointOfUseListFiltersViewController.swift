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

typealias Item = PointOfUseListFilter

class PointOfUseListFiltersViewController: UIViewController {
    class PointOfUseListFiltersDataSource: UITableViewDiffableDataSource<Section, Item> {
        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            if #available(iOS 15.0, *) {
                if let identifier = sectionIdentifier(for: section) {
                    return identifier.title
                }
            } else {
                let identifier = snapshot().sectionIdentifiers[section]
                return identifier.title
            }
            
            return nil
        }
    }
    
    enum Section: CaseIterable {
        case paymentType
        case sortBy
        case location
        case radius
        case locationService
        case resetFilters
        
        var title: String? {
            switch self {
            case .paymentType: return NSLocalizedString("Payment Type", comment: "Explore Dash/Merchants/Filters")
            case .sortBy: return NSLocalizedString("Sort by", comment: "Explore Dash/Merchants/Filters")
            case .location: return NSLocalizedString("Location", comment: "Explore Dash/Merchants/Filters")
            case .radius: return NSLocalizedString("Radius", comment: "Explore Dash/Merchants/Filters")
            case .locationService: return NSLocalizedString("Current Location Settings", comment: "Explore Dash/Merchants/Filters")
            default:
                return nil
            }
        }
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
    
    private var model = PointOfUseListFiltersModel()
    private var dataSource: PointOfUseListFiltersDataSource! = nil
    private var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>! = nil
    
    
    @IBOutlet var tableView: UITableView!
    
    @IBAction func cancelAction() {
        dismiss(animated: true)
    }
    
    @IBAction func applyAction() {
        dismiss(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        
        let navBar = self.navigationController!.navigationBar
        navBar.isTranslucent = true
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance
        
        super.viewWillAppear(animated)
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

//MARK: UITableViewDelegate
extension PointOfUseListFiltersViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let identifier: Section?
        
        if #available(iOS 15.0, *) {
            identifier = dataSource.sectionIdentifier(for: indexPath.section)
        } else {
            identifier = dataSource.snapshot().sectionIdentifiers[indexPath.section]
        }
        
        
        if let filterCell = tableView.cellForRow(at: indexPath) as? FilterItemSelectableCell,
           let item = dataSource.itemIdentifier(for: indexPath) {
            model.toggle(filter: item)
            return
        }
        
        if let identifier = identifier, identifier == .location {
            navigationController?.pushViewController(TerritoriesListViewController.controller(), animated: true)
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let dataSource = self.dataSource else { return nil }
        
        let title: String?
        
        if #available(iOS 15.0, *) {
            if let identifier = dataSource.sectionIdentifier(for: section) {
                title = identifier.title
            }else{
                title = nil
            }
        } else {
            let identifier = dataSource.snapshot().sectionIdentifiers[section]
            title = identifier.title
        }
        
        let label = UILabel()
        label.font = .dw_font(forTextStyle: .subheadline).withWeight(UIFont.Weight.medium.rawValue)
        label.textColor = .secondaryLabel
        label.text = title
        label.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIView()
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            label.topAnchor.constraint(equalTo: view.topAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        return view
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 30
    }
}

extension PointOfUseListFiltersViewController {
    private func configureHierarchy() {
        title = NSLocalizedString("Filters", comment: "Explore Dash")
        
        tableView.allowsMultipleSelection = true
        tableView.delegate = self
        
        view.backgroundColor = .dw_secondaryBackground()
    }
    
    private func configureDataSource() {
        self.dataSource = PointOfUseListFiltersDataSource(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: Item) -> UITableViewCell? in
            
            guard let wSelf = self else { return UITableViewCell() }
            
            let section = wSelf.currentSnapshot.sectionIdentifiers[indexPath.section]
            let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier, for: indexPath)
            cell.selectionStyle = .none
            
            if let filterCell = cell as? FilterItemCell {
                filterCell.update(with: item)
            }
            
            if let filterCell = cell as? FilterItemSelectableCell {
                filterCell.setSelected(wSelf.model.isFilterSelected(item), animated: true)
            }

            
            return cell
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

extension PointOfUseListFiltersViewController: TerritoriesListViewControllerDelegate {
    func didSelectTerritory(_ territory: Territory) {
        
    }
    
    func didSelectCurrentLocation() {
        
    }
}

//MARK: FilterItemSelectableCell
class FilterItemSelectableCell: FilterItemCell {
    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var checkboxButton: UIButton!
    
    override func update(with item: Item) {
        super.update(with: item)
        
        if let image = item.image {
            iconImageView.image = UIImage(named: image)
            iconImageView.isHidden = false
        }else{
            iconImageView.isHidden = true
        }
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        checkboxButton.isSelected = selected
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        checkboxButton.isUserInteractionEnabled = false
    }
}

//MARK: FilterItemCell
class FilterItemCell: UITableViewCell {
    @IBOutlet var nameLabel: UILabel!
    
    func update(with item: Item) {
        nameLabel.text = item.title
    }
}
