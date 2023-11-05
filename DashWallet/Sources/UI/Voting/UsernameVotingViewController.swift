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

import Foundation
import Combine

class UsernameVotingViewController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private var viewModel: VotingViewModel = VotingViewModel.shared
    
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var tableView: UITableView!
    @IBOutlet private var filterView: UIView!
    @IBOutlet private var filterViewTitle: UILabel!
    @IBOutlet private var filterViewSubtitle: UILabel!
    
    private var dataSource: DataSource! = nil
    
    var headerView: VotingHeaderView? {
        tableView.tableHeaderView as? VotingHeaderView
    }
    
    @objc
    static func controller() -> UsernameVotingViewController {
        vc(UsernameVotingViewController.self, from: sb("UsernameVoting"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureLayout()
        configureDataSource()
        configureObservers()
    }
    
    override func viewDidLayoutSubviews() {
        if viewModel.shouldShowFirstTimeInfo {
            viewModel.shouldShowFirstTimeInfo = false
            
            let alert = UIAlertController(title: NSLocalizedString("Vote only on duplicates", comment: "Voting"), message: NSLocalizedString("You can review all requests but you only need to vote on duplicates", comment: "Voting"), preferredStyle: .alert)
            let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel)
            alert.addAction(okAction)
            present(alert, animated: true)
        }
    }
    
    @IBAction
    func showFilters() {
        let vc = VotingFiltersViewController.controller()
        vc.delegate = self
        vc.filters = viewModel.filters
        
        let nvc = UINavigationController(rootViewController: vc)
        present(nvc, animated: true)
    }
}

extension UsernameVotingViewController {
    private func configureLayout() {
        titleLabel.text = NSLocalizedString("Username voting", comment: "Voting")
        titleLabel.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(mockData))
        titleLabel.addGestureRecognizer(tap)
        
        tableView.estimatedRowHeight = 200
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.register(GroupedRequestCell.self, forCellReuseIdentifier: GroupedRequestCell.description())
        
        let headerNib = UINib(nibName: "VotingHeaderView", bundle: nil)
        
        if let headerView = headerNib.instantiate(withOwner: nil, options: nil).first as? VotingHeaderView {
            tableView.tableHeaderView = headerView
            headerView.filterButtonHandler = { [weak self] in
                self?.showFilters()
            }
        }
        
        filterView.addTopBorder(with: UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1), andWidth: 1)
        filterViewTitle.text = NSLocalizedString("Filtered by", comment: "")
    }
    
    private func configureObservers() {
        viewModel.$groupedRequests
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.headerView?.set(duplicateAmount: data.count)
                self?.reloadDataSource(data: data)
            }
            .store(in: &cancellableBag)
    }
    
    @objc func mockData() {
        viewModel.addMockRequest()
    }
}

extension UsernameVotingViewController: HeightChangedDelegate {
    func heightChanged() {
        tableView.performBatchUpdates(nil)
    }
}

extension UITableView {
    public override var intrinsicContentSize: CGSize {
        layoutIfNeeded()
        return contentSize
    }

    public override var contentSize: CGSize {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }
}

extension UsernameVotingViewController: VotingFiltersViewControllerDelegate {
    func apply(filters: VotingFilters) {
        viewModel.apply(filters: filters)
        headerView?.set(filterLabel: filters.filterBy?.localizedString ?? "")
        filterViewSubtitle.text = filters.localizedDescription
    }
}

extension UsernameVotingViewController {
    enum Section: CaseIterable {
        case main
    }
    
    class DataSource: UITableViewDiffableDataSource<Section, GroupedUsernames> { }
    
    private func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: GroupedUsernames) -> UITableViewCell? in

            guard self != nil else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: GroupedRequestCell.description(), for: indexPath)

            if let groupedCell = cell as? GroupedRequestCell {
                groupedCell.configure(withModel: item.requests)
                groupedCell.heightDelegate = self
            }

            return cell
        }
    }
    
    private func reloadDataSource(data: [GroupedUsernames]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, GroupedUsernames>()
        snapshot.appendSections([.main])
        snapshot.appendItems(data)
        dataSource.apply(snapshot, animatingDifferences: false)
        dataSource.defaultRowAnimation = .none
    }
}

extension UIView {
    func addTopBorder(with color: UIColor, andWidth borderWidth: CGFloat) {
        let border = CALayer()
        border.backgroundColor = color.cgColor
        border.frame = CGRect(x: 0, y: 0, width: self.frame.size.width, height: borderWidth)
        self.layer.addSublayer(border)
    }
}
