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

class UsernameVotingViewController: UIViewController {
    @objc
    static func controller() -> UsernameVotingViewController {
        vc(UsernameVotingViewController.self, from: sb("UsernameVoting"))
    }
    
    override func viewDidLayoutSubviews() {
        let alert = UIAlertController(title: NSLocalizedString("Vote only on duplicates", comment: "Voting"), message: NSLocalizedString("You can review all requests but you only need to vote on duplicates", comment: "Voting"), preferredStyle: .alert)
        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel)
        alert.addAction(okAction)
        present(alert, animated: true)
    }
}
