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

final class OnlineAccountInfoController: UIViewController {
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var recoveryTitle: UILabel!
    @IBOutlet var recoveryDescription: UILabel!
    @IBOutlet var historyTitle: UILabel!
    @IBOutlet var historyDescription: UILabel!
    @IBOutlet var payoutTitle: UILabel!
    @IBOutlet var payoutDescription: UILabel!
    @IBOutlet var continueButton: UIButton!
    
    @objc
    static func controller() -> OnlineAccountInfoController {
        vc(OnlineAccountInfoController.self, from: sb("CrowdNode"))
    }

    @IBAction
    func continueAction() {
        navigationController?.replaceLast(1, with: OnlineAccountEmailController.controller())
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
}

extension OnlineAccountInfoController {
    private func configureHierarchy() {
        titleLabel.text = NSLocalizedString("Why do you need an online account?", comment: "CrowdNode")
        recoveryTitle.text = NSLocalizedString("Account Recovery", comment: "CrowdNode")
        recoveryDescription.text = NSLocalizedString("If you ever lose your passphrase, you can verify yourself by other means to regain access to your CrowdNode funds.", comment: "CrowdNode")
        historyTitle.text = NSLocalizedString("Transaction History", comment: "CrowdNode")
        historyDescription.text = NSLocalizedString("You can see detailed information about your deposits, withdrawals and reward earnings.", comment: "CrowdNode")
        payoutTitle.text = NSLocalizedString("Payout Options", comment: "CrowdNode")
        payoutDescription.text = NSLocalizedString("You can change how / when your reward earnings are paid to you.", comment: "CrowdNode")
        continueButton.setTitle(NSLocalizedString("Continue", comment: ""), for: .normal)
    }
}
