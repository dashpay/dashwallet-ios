//  
//  Created by Andrei Ashikhmin
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

import CoreLocation
import UIKit

// MARK: - VotingFiltersViewControllerDelegate

protocol VotingFiltersViewControllerDelegate: AnyObject {
    func apply(filters: VotingFilters)
}

// MARK: - VotingFiltersViewController

class VotingFiltersViewController: UIViewController {
    class DataSource: UITableViewDiffableDataSource<Section, VotingFilterItem> {
        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            if let identifier = sectionIdentifier(for: section) {
                return identifier.title
            }

            return nil
        }
    }

    enum Section: CaseIterable {
        case sortBy
        case approvedType
        case onlyDuplicates
        case onlyRequestsWithLinks
        case resetFilters

        var title: String? {
            switch self {
            case .approvedType: return NSLocalizedString("Type", comment: "Voting")
            case .sortBy: return NSLocalizedString("Sort by", comment: "Voting")
            default:
                return nil
            }
        }
        
        var items: [VotingFilterItem] {
            switch self {
            case .sortBy:
                return [.dateDesc, .dateAsc, .votesDesc, .votesAsc]
            case .approvedType:
                return [.typeAll, .typeApproved, .typeNotApproved]
            case .onlyDuplicates:
                return [.onlyDuplicates]
            case .onlyRequestsWithLinks:
                return [.onlyRequestsWithLinks]
            case .resetFilters:
                return [.reset]
            }
        }
    }

    public weak var delegate: VotingFiltersViewControllerDelegate?

    private var model = VotingFiltersModel()
    private var dataSource: DataSource! = nil
    private var currentSnapshot: NSDiffableDataSourceSnapshot<Section, VotingFilterItem>! = nil
    private var selectedCells: [VotingFilterItem: UITableViewCell] = [:]

    var filters: VotingFilters? {
        didSet {
            model.selected = filters?.items ?? []
            model.initialFilters = filters?.items ?? []
        }
    }

    @IBOutlet var tableView: UITableView!
    @IBOutlet var applyButton: UIBarButtonItem!
    @IBOutlet var cancelButton: UIBarButtonItem!

    private weak var resetCell: FilterItemResetCell?

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

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        configureDataSource()
        reloadDataSource()
    }

    class func controller() -> VotingFiltersViewController {
        VotingFiltersViewController.initiate(from: sb("UsernameVoting"))
    }
}

// MARK: UITableViewDelegate

extension VotingFiltersViewController: UITableViewDelegate {
    func toggleCells(for items: [VotingFilterItem]) {
        for item in items {
            if let cell = selectedCells[item] {
                cell.setSelected(false, animated: false)
                selectedCells[item] = nil
            }
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let filterCell = cell as? VotingFilterItemSelectableCell, let item = dataSource.itemIdentifier(for: indexPath), model.isFilterSelected(item) {
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
        if cell is VotingFilterItemSelectableCell,
           let item = dataSource.itemIdentifier(for: indexPath) {
            selectedCells[item] = nil
        }

        if cell is FilterItemResetCell {
            resetCell = nil
            return
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.cellForRow(at: indexPath) is VotingFilterItemSelectableCell, let item = dataSource.itemIdentifier(for: indexPath) {
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

        if let filterCell = tableView.cellForRow(at: indexPath) as? VotingFilterItemSelectableCell,
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

        if let identifier, identifier == .resetFilters {
            model.resetFilters()
            updateApplyButton()
            updateResetButton()
            tableView.reloadData()
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let dataSource else { return nil }

        let identifier = dataSource.identifier(for: section)
        let title = identifier?.title

        let label = UILabel()
        label.font = .dw_mediumFont(ofSize: 13)
        label.textColor = .dw_tertiaryText()
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
        if section < 2 {
            return 30
        }
        
        return CGFloat.leastNonzeroMagnitude
    }
}

extension VotingFiltersViewController {
    private func configureHierarchy() {
        title = NSLocalizedString("Filters", comment: "")

        tableView.allowsMultipleSelection = true
        tableView.delegate = self

        view.backgroundColor = .dw_secondaryBackground()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.dw_mediumFont(ofSize: 14)
        ]
        cancelButton.setTitleTextAttributes(attributes, for: .normal)
        applyButton.setTitleTextAttributes(attributes, for: .normal)
        cancelButton.setTitleTextAttributes(attributes, for: .selected)
        applyButton.setTitleTextAttributes(attributes, for: .selected)
        applyButton.setTitleTextAttributes(attributes, for: .disabled)
        
        updateApplyButton()
        updateResetButton()
    }

    private func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: VotingFilterItem) -> UITableViewCell? in

            guard self != nil else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier, for: indexPath)
            cell.selectionStyle = .none

            if let filterCell = cell as? VotingFilterItemSelectableCell {
                filterCell.update(with: item)
            }

            return cell
        }
    }

    func reloadDataSource() {
        let sections: [Section] = [.sortBy, .approvedType, .onlyDuplicates, .onlyRequestsWithLinks, .resetFilters]

        currentSnapshot = NSDiffableDataSourceSnapshot<Section, VotingFilterItem>()
        currentSnapshot.appendSections(sections)

        for group in sections {
            currentSnapshot.appendItems(group.items, toSection: group)
        }

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


extension VotingFiltersViewController.DataSource {
    final func identifier(for section: Int) -> VotingFiltersViewController.Section? {
        let identifier: VotingFiltersViewController.Section?

        if #available(iOS 15.0, *) {
            identifier = self.sectionIdentifier(for: section)
        } else {
            identifier = snapshot().sectionIdentifiers[section]
        }

        return identifier
    }
}
