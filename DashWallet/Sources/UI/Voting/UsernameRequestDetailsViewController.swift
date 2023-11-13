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

import Combine

class UsernameRequestDetailsViewController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private var viewModel: VotingViewModel = VotingViewModel.shared
    private var request: UsernameRequest!
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var usernameLabel: UILabel!
    @IBOutlet var username: UILabel!
    @IBOutlet var linkLabel: UILabel!
    @IBOutlet var link: UILabel!
    @IBOutlet var linkPanel: UIView!
    @IBOutlet var identityLabel: UILabel!
    @IBOutlet var identity: UILabel!
    @IBOutlet var voteButton: ActionButton!
    
    static func controller(with request: UsernameRequest) -> UsernameRequestDetailsViewController {
        let vc = vc(UsernameRequestDetailsViewController.self, from: sb("UsernameVoting"))
        vc.request = request
        
        return vc
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
    }
    
    @IBAction
    func voteAction() {
        let vc: UIViewController
        
        if viewModel.masternodeKeys.isEmpty {
            vc = EnterVotingKeyViewController.controller()
        } else {
            vc = CastVoteViewController.controller()
        }
        
        self.navigationController?.pushViewController(vc, animated: true)
    }
}


extension UsernameRequestDetailsViewController {
    private func configureLayout() {
        titleLabel.text = NSLocalizedString("Request details", comment: "Voting")
        subtitleLabel.text = NSLocalizedString("Review the posting below to verify the ownership of this username", comment: "Voting")
        usernameLabel.text = NSLocalizedString("Username", comment: "Voting")
        linkLabel.text = NSLocalizedString("Link", comment: "Voting")
        identityLabel.text = NSLocalizedString("Identity", comment: "Voting")
        voteButton.setTitle(NSLocalizedString("Vote to Approve", comment: "Voting"), for: .normal)
        
        username.text = request.username
        identity.text = request.identity
        
        if let url = request.link {
            link.text = url
            linkPanel.isHidden = false
            let linkTap = UITapGestureRecognizer(target: self, action: #selector(openLink))
            linkPanel.addGestureRecognizer(linkTap)
        }
    }
    
    @objc
    private func openLink() {
        if let url = request.link {
            UIApplication.shared.open(URL(string: url)!)
        }
    }
}
