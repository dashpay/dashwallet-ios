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

class VotingInfoViewController: UIViewController {
    private let viewModel = RequestUsernameViewModel.shared
    
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var subtitleLabel: UILabel!
    @IBOutlet private var timelineTitle: UILabel!
    @IBOutlet private var timelineSubtitle: UILabel!
    @IBOutlet private var notApprovedTitle: UILabel!
    @IBOutlet private var notApprovedSubtitle: UILabel!
    @IBOutlet private var passphraseTitle: UILabel!
    @IBOutlet private var passphraseSubtitle: UILabel!
    @IBOutlet private var continueButton: UIButton!
    
    private var goBackOnClose: Bool!
    
    @objc
    static func controller(goBackOnClose: Bool) -> VotingInfoViewController {
        let vc = vc(VotingInfoViewController.self, from: sb("UsernameRequests"))
        vc.goBackOnClose = goBackOnClose
        return vc
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
    }
    
    @IBAction
    func continueAction() {
        viewModel.shouldShowFirstTimeInfo = false
        
        if goBackOnClose {
            self.navigationController?.popViewController(animated: true)
        } else {
            let vc = RequestUsernameViewController.controller()
            vc.hidesBottomBarWhenPushed = true
            self.navigationController?.replaceLast(2, with: vc, animated: true)
        }
    }
}

extension VotingInfoViewController {
    private func configureLayout() {
        titleLabel.text = NSLocalizedString("What is username voting?", comment: "Usernames")
        subtitleLabel.text = NSLocalizedString("The Dash network must vote to approve your username before it is created.", comment: "Usernames")
        
        timelineTitle.text = NSLocalizedString("Voting will not be required forever", comment: "Usernames")
        let endDate = Date(timeIntervalSince1970: 1700391858)
        timelineSubtitle.text = String.localizedStringWithFormat(NSLocalizedString("After voting is completed on %@ you can create any username that has not already been created", comment: "Usernames"), DWDateFormatter.sharedInstance.shortString(from: endDate))
        
        notApprovedTitle.text = NSLocalizedString("In case your request is not approved", comment: "Usernames")
        notApprovedSubtitle.text = NSLocalizedString("Pay now and if not approved, you can create a different name without paying again", comment: "Usernames")
        
        passphraseTitle.text = NSLocalizedString("Keep your passphrase safe", comment: "Usernames")
        passphraseSubtitle.text = NSLocalizedString("In case you lose your passphrase you will lose your right to your requested username.", comment: "Usernames")
        
        continueButton.setTitle(NSLocalizedString("OK", comment: ""), for: .normal)
    }
}
