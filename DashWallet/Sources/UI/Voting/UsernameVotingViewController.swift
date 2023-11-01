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
    private var disposableBag = Set<AnyCancellable>()
    private var viewModel: VotingViewModel = VotingViewModel.shared
    
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var tableView: UITableView!
    
    @objc
    static func controller() -> UsernameVotingViewController {
        vc(UsernameVotingViewController.self, from: sb("UsernameVoting"))
    }
    
    override func viewDidLoad() {
        configureLayout()
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
        tableView.dataSource = self
        tableView.delegate = self
        
        let headerNib = UINib(nibName: "VotingHeaderView", bundle: nil)
        
        if let customHeaderView = headerNib.instantiate(withOwner: nil, options: nil).first as? UIView {
            tableView.tableHeaderView = customHeaderView
        }
    }
    
    @objc func mockData() {
        viewModel.addMockRequest()
        tableView.reloadData()
    }
}

//MARK: UITableViewDelegate, UITableViewDataSource

extension UsernameVotingViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.duplicates.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: GroupedRequestCell.description(), for: indexPath)
        guard let cell = cell as? GroupedRequestCell else { return UITableViewCell() }
        
        let username = viewModel.duplicates[indexPath.row]
        let requests = viewModel.getAllRequests(for: username)
        cell.configure(withModel: requests)
        cell.heightDelegate = self
        
        return cell
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
