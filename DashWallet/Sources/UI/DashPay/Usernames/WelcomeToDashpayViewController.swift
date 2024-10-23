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

class WelcomeToDashPayViewController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel = RequestUsernameViewModel.shared
    
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var createUsernameTitle: UILabel!
    @IBOutlet private var createUsernameSubtitle: UILabel!
    @IBOutlet private var addFriendsTitle: UILabel!
    @IBOutlet private var addFriendsSubtitle: UILabel!
    @IBOutlet private var profileTitle: UILabel!
    @IBOutlet private var profileSubtitle: UILabel!
    @IBOutlet private var minimumBalanceLabel: UILabel!
    @IBOutlet private var continueButton: UIButton!
    
    @objc
    static func controller() -> WelcomeToDashPayViewController {
        vc(WelcomeToDashPayViewController.self, from: sb("UsernameRequests"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
        configureObservers()
    }
    
    @IBAction
    func continueAction() {
        self.navigationController?.pushViewController(VotingInfoViewController.controller(goBackOnClose: false), animated: true)
    }
}

extension WelcomeToDashPayViewController {
    private func configureLayout() {
        titleLabel.text = NSLocalizedString("Welcome to Dash Pay", comment: "Usernames")
        createUsernameTitle.text = NSLocalizedString("Create a username", comment: "Usernames")
        createUsernameSubtitle.text = NSLocalizedString("Pay to usernames. No more alphanumeric addresses.", comment: "Usernames")
        addFriendsTitle.text = NSLocalizedString("Add your friends & family", comment: "Usernames")
        addFriendsSubtitle.text = NSLocalizedString("Invite your family, find your friends by searching their usernames.", comment: "Usernames")
        profileTitle.text = NSLocalizedString("Personalise profile", comment: "Usernames")
        profileSubtitle.text = NSLocalizedString("Upload your picture, personalize your identity.", comment: "Usernames")
        continueButton.setTitle(NSLocalizedString("Continue", comment: "Usernames"), for: .normal)
    }
    
    func configureObservers() {
        viewModel.$hasMinimumRequiredBalance
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] hasEnough in
                guard let self = self else { return }
                self.refreshBalanceWarning(enoughBalance: hasEnough)
            })
            .store(in: &cancellableBag)
    }
    
    private func refreshBalanceWarning(enoughBalance: Bool) {
        continueButton.isEnabled = enoughBalance
        minimumBalanceLabel.isHidden = enoughBalance
        minimumBalanceLabel.text = String.localizedStringWithFormat(NSLocalizedString("You should have more than %@ Dash to create a username", comment: "Usernames"), viewModel.minimumRequiredBalance)
    }
}
