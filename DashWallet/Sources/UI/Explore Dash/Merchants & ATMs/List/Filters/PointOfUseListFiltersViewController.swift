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

import CoreLocation
import UIKit

typealias Item = PointOfUseListFilterItem

// MARK: - PointOfUseListFiltersGroup

public enum PointOfUseListFiltersGroup {
    case paymentType
    case sortByDistanceOrName

    case sortByName
    case territory
    case radius
    case locationService

    var section: PointOfUseListFiltersViewController.Section {
        switch self {
        case .paymentType:
            return .paymentType
        case .sortByName, .sortByDistanceOrName:
            return .sortBy
        case .territory:
            return .location
        case .radius:
            return .radius
        case .locationService:
            return .locationService
        }
    }

    var items: [PointOfUseListFilterItem] {
        switch self {
        case .paymentType:
            return [.paymentTypeDash, .paymentTypeGiftCard]
        case .sortByName:
            return [.sortAZ, .sortZA]
        case .sortByDistanceOrName:
            return [.sortDistance, .sortName]
        case .territory:
            return [.location]
        case .locationService:
            return [.locationService]
        case .radius:
            return [.radius1, .radius5, .radius20, .radius50]
        }
    }
}

// MARK: - PointOfUseListFiltersViewControllerDelegate

protocol PointOfUseListFiltersViewControllerDelegate: AnyObject {
    func apply(filters: PointOfUseListFilters?)
}

// MARK: - PointOfUseListFiltersViewController

class PointOfUseListFiltersViewController: UIViewController {
    class DataSource: UITableViewDiffableDataSource<Section, Item> {
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
            case .locationService: return NSLocalizedString("Current Location Settings",
                                                            comment: "Explore Dash/Merchants/Filters")
            default:
                return nil
            }
        }


    }

    public weak var delegate: PointOfUseListFiltersViewControllerDelegate?

    private var model = PointOfUseListFiltersModel()
    private var dataSource: DataSource! = nil
    private var currentSnapshot: NSDiffableDataSourceSnapshot<Section, Item>! = nil
    private var selectedCells: [Item: UITableViewCell] = [:]

    var territoriesDataSource: TerritoryDataSource?
    var filtersToUse: [PointOfUseListFiltersGroup]!
    var filters: PointOfUseListFilters? {
        didSet {
            model.selected = filters?.items ?? []
            model.initialFilters = filters?.items ?? []
            model.initialSelectedTerritory = filters?.territory
        }
    }

    var defaultFilters: PointOfUseListFilters? {
        didSet {
            model.defaultFilters = defaultFilters?.items ?? []
        }
    }

    @IBOutlet var tableView: UITableView!
    @IBOutlet var applyButton: UIBarButtonItem!

    private weak var resetCell: FilterItemResetCell?

    init(filters: [PointOfUseListFiltersGroup]) {
        filtersToUse = filters

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @IBAction
    func cancelAction() {
        dismiss(animated: true)
    }

    @IBAction
    func applyAction() {
        delegate?.apply(filters: model.appliedFilters)
        dismiss(animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        DWLocationManager.shared.add(observer: self)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()

        let navBar = navigationController!.navigationBar
        navBar.isTranslucent = true
        navBar.standardAppearance = appearance
        navBar.scrollEdgeAppearance = appearance

        super.viewWillAppear(animated)
    }


    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        DWLocationManager.shared.remove(observer: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        configureDataSource()
        reloadDataSource()
    }

    class func controller() -> PointOfUseListFiltersViewController {
        let storyboard = UIStoryboard(name: "ExploreDash", bundle: nil)
        return storyboard
            .instantiateViewController(withIdentifier: "PointOfUseListFiltersViewController") as! PointOfUseListFiltersViewController
    }
}

// MARK: UITableViewDelegate

extension PointOfUseListFiltersViewController: UITableViewDelegate {
    func toggleCells(for items: [Item]) {
        for item in items {
            if let cell = selectedCells[item] {
                cell.setSelected(false, animated: false)
                selectedCells[item] = nil
            }
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let filterCell = cell as? FilterItemSelectableCell,
           let item = dataSource.itemIdentifier(for: indexPath),
           model.isFilterSelected(item) {
            tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            filterCell.setSelected(true, animated: true)
            selectedCells[item] = filterCell
            return
        }

        if let cell = cell as? FilterItemResetCell {
            cell.isEnabled = model.canReset
            resetCell = cell
            return
        }
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if cell is FilterItemSelectableCell,
           let item = dataSource.itemIdentifier(for: indexPath) {
            selectedCells[item] = nil
        }

        if cell is FilterItemResetCell {
            resetCell = nil
            return
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.cellForRow(at: indexPath) is FilterItemSelectableCell,
           let item = dataSource.itemIdentifier(for: indexPath) {
            let deselected = model.toggle(filter: item)
            if !deselected {
                tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            }
            updateApplyButton()
            updateResetButton()
            return
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let identifier = dataSource.identifier(for: indexPath.section)

        if let filterCell = tableView.cellForRow(at: indexPath) as? FilterItemSelectableCell,
           let item = dataSource.itemIdentifier(for: indexPath) {
            selectedCells[item] = filterCell
            let selected = model.toggle(filter: item)
            if !selected {
                tableView.deselectRow(at: indexPath, animated: true)
            }

            updateApplyButton()
            updateResetButton()
            toggleCells(for: item.itemsToUnselect)
            return
        }

        if let identifier, identifier == .locationService {
            UIApplication.shared.open(URL(string:UIApplication.openSettingsURLString)!)
            return
        }

        if let identifier, identifier == .resetFilters {
            model.resetFilters()
            updateApplyButton()
            updateResetButton()
            tableView.reloadData()
            return
        }

        if let identifier, identifier == .location {
            let vc = TerritoriesListViewController.controller()
            vc.selectedTerritory = model.selectedTerritory
            vc.territoriesDataSource = territoriesDataSource
            vc.delegate = self
            navigationController?.pushViewController(vc, animated: true)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let dataSource else { return nil }

        let identifier = dataSource.identifier(for: section)
        let title = identifier?.title

        let label = UILabel()
        label.font = .dw_font(forTextStyle: .subheadline).withWeight(UIFont.Weight.medium.rawValue)
        label.textColor = .dw_secondaryText()
        label.text = title
        label.translatesAutoresizingMaskIntoConstraints = false

        let view = UIView()
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            label.topAnchor.constraint(equalTo: view.topAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        30
    }
}

extension PointOfUseListFiltersViewController {
    private func configureHierarchy() {
        title = NSLocalizedString("Filters", comment: "Explore Dash")

        tableView.allowsMultipleSelection = true
        tableView.delegate = self

        view.backgroundColor = .dw_secondaryBackground()

        updateApplyButton()
        updateResetButton()
    }

    private func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: Item) -> UITableViewCell? in

                guard let wSelf = self else { return UITableViewCell() }

                let section = wSelf.currentSnapshot.sectionIdentifiers[indexPath.section]
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier, for: indexPath)
                cell.selectionStyle = .none

                if let filterCell = cell as? FilterItemCell {
                    if section == .location {
                        filterCell.nameLabel.text = self?.model.selectedTerritory ?? item.title
                    } else {
                        filterCell.update(with: item)
                    }
                }

                return cell
        }
    }

    func reloadDataSource() {
        var sections = filtersToUse.map { $0.section }
        sections.append(.resetFilters)

        if !DWLocationManager.shared.isAuthorized {
            sections = sections.filter { $0 != .radius }
        }

        currentSnapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        currentSnapshot.appendSections(sections)

        for group in filtersToUse {
            if DWLocationManager.shared.isAuthorized || group.section != .radius {
                currentSnapshot.appendItems(group.items, toSection: group.section)
            }
        }

        currentSnapshot.appendItems([.reset], toSection: .resetFilters)

        dataSource.apply(currentSnapshot, animatingDifferences: false)
        dataSource.defaultRowAnimation = .none
    }

    private func updateApplyButton() {
        applyButton.isEnabled = model.canApply
    }

    private func updateResetButton() {
        resetCell?.isEnabled = model.canReset
    }
}

// MARK: TerritoriesListViewControllerDelegate

extension PointOfUseListFiltersViewController: TerritoriesListViewControllerDelegate {
    func didSelectTerritory(_ territory: Territory) {
        model.select(territory: territory)
        tableView.reloadData()
        updateApplyButton()
        updateResetButton()
        navigationController?.popViewController(animated: true)
    }

    func didSelectCurrentLocation() {
        model.select(territory: nil)
        tableView.reloadData()
        updateApplyButton()
        updateResetButton()
        navigationController?.popViewController(animated: true)
    }
}


// MARK: DWLocationObserver

extension PointOfUseListFiltersViewController: DWLocationObserver {
    func locationManagerDidChangeCurrentLocation(_ manager: DWLocationManager, location: CLLocation) { }

    func locationManagerDidChangeCurrentReversedLocation(_ manager: DWLocationManager) { }

    func locationManagerDidChangeServiceAvailability(_ manager: DWLocationManager) {
        tableView.reloadData()
        updateApplyButton()
        updateResetButton()
    }
}

// MARK: - FilterItemSelectableCell

class FilterItemSelectableCell: FilterItemCell {
    @IBOutlet var iconImageView: UIImageView!
    @IBOutlet var checkboxButton: UIButton!

    override func update(with item: Item) {
        super.update(with: item)

        if let image = item.image {
            iconImageView.image = UIImage(named: image)
            iconImageView.isHidden = false
        } else {
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


// MARK: - FilterItemCell

class FilterItemCell: UITableViewCell {
    @IBOutlet var nameLabel: UILabel!

    func update(with item: Item) {
        nameLabel.text = item.title
    }
}

// MARK: - FilterItemResetCell

class FilterItemResetCell: UITableViewCell {
    @IBOutlet var resetLabel: UILabel!

    var isEnabled = true {
        didSet {
            resetLabel.textColor = isEnabled ? .dw_red() : .dw_secondaryText()
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        resetLabel.isUserInteractionEnabled = false
        resetLabel.text = NSLocalizedString("Reset Filters", comment: "Explore Dash")
    }
}

extension PointOfUseListFiltersViewController.DataSource {
    final func identifier(for section: Int) -> PointOfUseListFiltersViewController.Section? {
        let identifier: PointOfUseListFiltersViewController.Section?

        if #available(iOS 15.0, *) {
            identifier = self.sectionIdentifier(for: section)
        } else {
            identifier = snapshot().sectionIdentifiers[section]
        }

        return identifier
    }
}
