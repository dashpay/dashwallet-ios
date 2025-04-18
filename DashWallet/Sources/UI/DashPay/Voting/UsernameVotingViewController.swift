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
    private var quickVotingButton: UIBarButtonItem!
    
    @objc func quickVoteActions() {
        present(QuickVoteViewController.controller(viewModel.filteredRequests.count), animated: true)
    }
    
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

        viewModel.refresh()
        apply(filters: VotingFilters.defaultFilters)
        configureLayout()
        configureDataSource()
        configureObservers()
    }
    
    override func viewDidLayoutSubviews() {
        if viewModel.shouldShowFirstTimeInfo {
            viewModel.shouldShowFirstTimeInfo = false
            showModalDialog(icon: .system("info"), heading: NSLocalizedString("Default filter setting", comment: "Voting"), textBlock1: NSLocalizedString("The default filter shows only duplicate usernames that you have NOT voted on, but you can see and vote on any contested username by changing the filter.", comment: "Voting"), positiveButtonText: NSLocalizedString("OK", comment: ""))
        }
    }
    
    @IBAction
    func showFilters() {
        view.endEditing(true)
        
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
        
        tableView.estimatedRowHeight = 50
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        tableView.allowsSelection = true
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInset.bottom = 50
        tableView.sectionHeaderTopPadding = 12
        tableView.register(GroupedRequestCell.self, forCellReuseIdentifier: GroupedRequestCell.description())
        tableView.register(UsernameRequestCell.self, forCellReuseIdentifier: UsernameRequestCell.description())
        
        let headerNib = UINib(nibName: "VotingHeaderView", bundle: nil)
        
        if let headerView = headerNib.instantiate(withOwner: nil, options: nil).first as? VotingHeaderView {
            tableView.tableHeaderView = headerView
            headerView.filterButtonHandler = { [weak self] in
                self?.showFilters()
            }
            headerView.set(searchQuerytChangedHandler: self)
        }
        
        filterView.addTopBorder(with: UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1), andWidth: 1)
        let filterViewTap = UITapGestureRecognizer(target: self, action: #selector(showFilters))
        filterView.addGestureRecognizer(filterViewTap)
        filterViewTitle.text = NSLocalizedString("Filtered by", comment: "")
        
        let button = UIBarButtonItem(title: NSLocalizedString("Quick Voting", comment: "Voting"), style: .plain, target: self, action: #selector(quickVoteActions))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.dw_mediumFont(ofSize: 13),
            .foregroundColor: UIColor.dw_dashBlue()
        ]
        button.setTitleTextAttributes(attributes, for: .normal)
        button.setTitleTextAttributes(attributes, for: .highlighted)
        self.quickVotingButton = button
    }
    
    private func configureObservers() {
        viewModel.$filteredRequests
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.updateQuickVoteButton()
                self?.headerView?.set(duplicateAmount: data.count)
                self?.reloadDataSource(data: data)
            }
            .store(in: &cancellableBag)
        
        viewModel.$lastVoteAction
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                switch action {
                case .approved:
                    self?.showToast(text: NSLocalizedString("Your vote was submitted", comment: "Voting"), icon: .system("checkmark.circle.fill"), duration: 2)
                case .revoked:
                    self?.showToast(text: NSLocalizedString("Your vote was cancelled", comment: "Voting"), icon: .system("checkmark.circle.fill"), duration: 2)
                case .blocked:
                    let username = self?.viewModel.selectedRequest?.username ?? ""
                    self?.showToast(text: String.localizedStringWithFormat(NSLocalizedString("Blocked '%@' username", comment: "Voting"), username), icon: .system("checkmark.circle.fill"), duration: 2)
                default:
                    break
                }
                self?.viewModel.onVoteActionHandled()
            }
            .store(in: &cancellableBag)
        
        viewModel.$masternodeKeys
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateQuickVoteButton()
            }
            .store(in: &cancellableBag)
    }
    
    @objc func mockData() {
        viewModel.addMockRequest()
    }
    
    private func updateQuickVoteButton() {
        let requests = viewModel.filteredRequests
        let keys = viewModel.masternodeKeys
        self.navigationItem.rightBarButtonItem = requests.isEmpty || keys.isEmpty ?
            nil : self.quickVotingButton
    }
    
    private func navigateToBlock(request: UsernameRequest) {
        viewModel.selectedRequest = request
        let vc: UIViewController
        
        if viewModel.masternodeKeys.isEmpty {
            vc = EnterVotingKeyViewController.controller(blocking: true)
        } else {
            vc = CastVoteViewController.controller(blocking: true)
        }
        
        self.navigationController?.pushViewController(vc, animated: true)
    }
}

extension UsernameVotingViewController: VotingFiltersViewControllerDelegate {
    func apply(filters: VotingFilters) {
        viewModel.apply(filters: filters)
        headerView?.set(filterLabel: filters.filterBy?.localizedString ?? "")
        filterViewSubtitle.text = filters.localizedDescription
    }
}

extension UsernameVotingViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath), item.requests.count == 1 else { return }
        
        openDetails(for: item.requests[0])
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView()
        headerView.backgroundColor = .clear
        
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = String.localizedStringWithFormat(NSLocalizedString("Voting ends in %dd", comment: "Voting"), dataSource.snapshot().sectionIdentifiers[section].votingEndsInDays)
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.textColor = .dw_tertiaryText()
        label.textAlignment = .center
        
        headerView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 0),
            label.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8)
        ])
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 25
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }
}

extension UsernameVotingViewController {
    struct Section: Hashable {
        let votingEndsInDays: Int
    }
    
    class DataSource: UITableViewDiffableDataSource<Section, GroupedUsernames> { }
    
    private func configureDataSource() {
        tableView.delegate = self
        dataSource = DataSource(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: GroupedUsernames) -> UITableViewCell? in

            guard self != nil else { return UITableViewCell() }
            
            if item.requests.count == 1 {
                let cell = tableView.dequeueReusableCell(withIdentifier: UsernameRequestCell.description(), for: indexPath)
                
                if let requestCell = cell as? UsernameRequestCell {
                    requestCell.configure(withModel: item.requests[0], isInGroup: false)
                    requestCell.onApproveTapped = { [weak self] request in
                        self?.openDetails(for: request)
                    }
                    requestCell.onBlockTapped = { [weak self] request in
                        self?.onBlockTapped(request: request)
                    }
                }
                
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: GroupedRequestCell.description(), for: indexPath)

                if let groupedCell = cell as? GroupedRequestCell {
                    groupedCell.configure(withModel: item.requests)
                    groupedCell.onHeightChanged = {
                        tableView.performBatchUpdates(nil)
                    }
                    groupedCell.onRequestSelected = { [weak self] request in
                        self?.openDetails(for: request)
                    }
                    groupedCell.onBlockTapped = { [weak self] request in
                        self?.onBlockTapped(request: request)
                    }
                }

                return cell
            }
        }
    }
    
    private func onBlockTapped(request: UsernameRequest) {
        if viewModel.masternodeKeys.isEmpty || request.blockVotes <= 0 {
            self.navigateToBlock(request: request)
        } else { // TODO: MOCK_DASHPAY replace with correct logic
            self.viewModel.unblock(request: request.requestId)
            self.showToast(text: String.localizedStringWithFormat(NSLocalizedString("Unblocked '%@' username", comment: "Voting"), request.username), icon: .system("checkmark.circle.fill"), duration: 2)
        }
    }
    
    private func reloadDataSource(data: [GroupedUsernames]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, GroupedUsernames>()
        let groupedData = Dictionary(grouping: data, by: { grouped in
            grouped.requests.sorted { $0.createdAt < $1.createdAt }.first.map { req in
                let twoWeeks = 14.0 * 24 * 60 * 60
                let endDate = Date(timeIntervalSince1970: TimeInterval(req.createdAt)).addingTimeInterval(twoWeeks)
                let days = max(0, Int(endDate.timeIntervalSinceNow / (24 * 60 * 60)))
                return days
            } ?? 0 // TODO: MOCK_DASHPAY might be incorrect logic for the vote ending date
        })
           
        for (votingEndsInDays, items) in groupedData {
            snapshot.appendSections([Section(votingEndsInDays: votingEndsInDays)])
            snapshot.appendItems(items)
        }
           
        dataSource.apply(snapshot, animatingDifferences: false)
        dataSource.defaultRowAnimation = .none
    }
    
    private func openDetails(for request: UsernameRequest) {
        let vc = UsernameRequestDetailsViewController.controller(with: request)
        self.navigationController?.pushViewController(vc, animated: true)
    }
}

extension UsernameVotingViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        viewModel.searchQuery = searchText
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
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

extension UIView {
    func addTopBorder(with color: UIColor, andWidth borderWidth: CGFloat) {
        let border = CALayer()
        border.backgroundColor = color.cgColor
        border.frame = CGRect(x: 0, y: 0, width: self.frame.size.width, height: borderWidth)
        self.layer.addSublayer(border)
    }
}
