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

class UsernameInfoViewController: UIViewController {
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var createUsernameTitle: UILabel!
    @IBOutlet private var createUsernameSubtitle: UILabel!
    @IBOutlet private var addFriendsTitle: UILabel!
    @IBOutlet private var addFriendsSubtitle: UILabel!
    @IBOutlet private var profileTitle: UILabel!
    @IBOutlet private var profileSubtitle: UILabel!
    @IBOutlet private var continueButton: UIButton!
    
    @objc
    static func controller() -> UsernameInfoViewController {
        vc(UsernameInfoViewController.self, from: sb("UsernameRequests"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
    }
}

extension UsernameInfoViewController {
    func configureLayout() {
        titleLabel.text = NSLocalizedString("Welcome to Dash Pay", comment: "Usernames")
        createUsernameTitle.text = NSLocalizedString("Create a username", comment: "Usernames")
        createUsernameSubtitle.text = NSLocalizedString("Pay to usernames. No more alphanumeric addresses.", comment: "Usernames")
        addFriendsTitle.text = NSLocalizedString("Add your friends & family", comment: "Usernames")
        addFriendsSubtitle.text = NSLocalizedString("Invite your family, find your friends by searching their usernames.", comment: "Usernames")
        profileTitle.text = NSLocalizedString("Personalise profile", comment: "Usernames")
        profileSubtitle.text = NSLocalizedString("Upload your picture, personalize your identity.", comment: "Usernames")
        continueButton.setTitle(NSLocalizedString("Continue", comment: "Usernames"), for: .normal)
    }
}
