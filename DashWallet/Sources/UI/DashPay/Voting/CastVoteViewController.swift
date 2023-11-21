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

import UIKit
import Combine

// MARK: - CastVoteViewController

final class CastVoteViewController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private var viewModel: VotingViewModel = VotingViewModel.shared
    
    private var dataSource: DataSource! = nil
    @IBOutlet private var tableView: UITableView!
    
    class func controller() -> CastVoteViewController {
        CastVoteViewController.initiate(from: sb("UsernameVoting"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureDataSource()
        configureObservers()
    }
}

extension CastVoteViewController {
    private func configureHierarchy() {
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
    }
    
    private func configureObservers() {
        viewModel.$masternodeKeys
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.reloadDataSource(keys: data)
            }
            .store(in: &cancellableBag)
    }
}

extension CastVoteViewController {
    @IBAction
    func addMasternodeKey() {
        let vc = EnterVotingKeyViewController.controller()
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    @IBAction
    func submit() {
        if let id = viewModel.selectedRequest?.requestId {
            viewModel.vote(for: id)
            self.navigationController?.popToViewController(ofType: UsernameVotingViewController.self, animated: true)
        }
    }
}

extension CastVoteViewController {
    enum Section: CaseIterable {
        case main
    }
    
    class DataSource: UITableViewDiffableDataSource<Section, MasternodeKey> { }
    
    private func configureDataSource() {
        dataSource = DataSource(tableView: tableView) { [weak self]
            (tableView: UITableView, indexPath: IndexPath, item: MasternodeKey) -> UITableViewCell? in

            guard self != nil else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(withIdentifier: "MasternodeIPCell", for: indexPath)

            if let ipCell = cell as? MasternodeIPCell {
                ipCell.update(with: item.ip)
            }

            return cell
        }
    }
    
    private func reloadDataSource(keys: [MasternodeKey]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, MasternodeKey>()
        snapshot.appendSections([.main])
        snapshot.appendItems(keys)
        dataSource.apply(snapshot, animatingDifferences: false)
        dataSource.defaultRowAnimation = .none
    }
}
