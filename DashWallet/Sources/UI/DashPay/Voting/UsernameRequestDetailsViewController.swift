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
    
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var usernameLabel: UILabel!
    @IBOutlet var username: UILabel!
    @IBOutlet var linkLabel: UILabel!
    @IBOutlet var link: UILabel!
    @IBOutlet var linkPanel: UIView!
    @IBOutlet var identityLabel: UILabel!
    @IBOutlet var identity: UILabel!
    @IBOutlet var voteButton: UIButton!
    
    static func controller(with request: UsernameRequest) -> UsernameRequestDetailsViewController {
        let vc = vc(UsernameRequestDetailsViewController.self, from: sb("UsernameVoting"))
        vc.setRequest(request)
        
        return vc
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
    }
    
    @IBAction
    func voteAction() {
        let vc: UIViewController
        
        if viewModel.selectedRequest?.isApproved == true {
            viewModel.revokeVote(of: viewModel.selectedRequest!.requestId)
            self.navigationController?.popViewController(animated: true)
            return
        } else if viewModel.masternodeKeys.isEmpty {
            vc = EnterVotingKeyViewController.controller()
        } else {
            let id = viewModel.selectedRequest!.requestId
            let votesLeft = viewModel.votesLeft(for: id)
            print("VOTING: votesLeft: \(votesLeft)")
            
            if votesLeft <= 1 {
                warnVotesLeft(votesLeft, for: id)
                return
            } else {
                vc = CastVoteViewController.controller()
            }
        }
        
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    private func setRequest(_ request: UsernameRequest) {
        viewModel.selectedRequest = request
    }
    
    private func warnVotesLeft(_ left: Int, for requestId: String) {
        guard left <= 1 else { return }
        
        let title = left == 0 ? NSLocalizedString("No votes left", comment: "Voting") : NSLocalizedString("One vote left", comment: "Voting")
        let message = left == 0 ? String.localizedStringWithFormat(NSLocalizedString("You have already voted for this username %ld times. You cannot vote for it anymore.", comment: "Voting"), VotingConstants.maxVotes) : String.localizedStringWithFormat(NSLocalizedString("You have already voted for this username %ld times. You can only cast one more vote for this username.", comment: "Voting"), VotingConstants.maxVotes - 1)

        showModalDialog(
            style: .warning,
            icon: .system("exclamationmark.triangle.fill"),
            heading: title,
            textBlock1: message,
            positiveButtonText: NSLocalizedString("OK", comment: "") ,
            positiveButtonAction: { [weak self] in
                if left > 0 {
                    let vc = CastVoteViewController.controller()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            },
            negativeButtonText: left == 0 ? nil : NSLocalizedString("Cancel", comment: "")
        )
    }
}


extension UsernameRequestDetailsViewController {
    private func configureLayout() {
        titleLabel.text = NSLocalizedString("Request details", comment: "Voting")
        subtitleLabel.text = NSLocalizedString("Review the posting below to verify the ownership of this username", comment: "Voting")
        usernameLabel.text = NSLocalizedString("Username", comment: "Voting")
        linkLabel.text = NSLocalizedString("Link", comment: "Voting")
        identityLabel.text = NSLocalizedString("Identity", comment: "Voting")
        
        if let request = viewModel.selectedRequest {
            username.text = request.username
            identity.text = request.identity
            
            if let url = request.link {
                link.text = url
                linkPanel.isHidden = false
                let linkTap = UITapGestureRecognizer(target: self, action: #selector(openLink))
                linkPanel.addGestureRecognizer(linkTap)
            }
            
            voteButton.layer.cornerRadius = 8
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.dw_mediumFont(ofSize: 15)
            ]
            
            if request.isApproved {
                voteButton.backgroundColor = .dw_red().withAlphaComponent(0.1)
                voteButton.tintColor = .dw_red()
                let attributedTitle = NSAttributedString(string: NSLocalizedString("Cancel Approval", comment: "Voting"), attributes: attributes)
                voteButton.setAttributedTitle(attributedTitle, for: .normal)
            } else {
                voteButton.backgroundColor = .dw_dashBlue()
                voteButton.tintColor = .white
                let attributedTitle = NSAttributedString(string: NSLocalizedString("Vote to Approve", comment: "Voting"), attributes: attributes)
                voteButton.setAttributedTitle(attributedTitle, for: .normal)
            }
        }
    }
    
    @objc
    private func openLink() {
        if let url = viewModel.selectedRequest?.link {
            UIApplication.shared.open(URL(string: url)!)
        }
    }
}
