//
//  Created by Andrei Ashikhmin
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

final class WelcomeToCrowdNodeViewController: BaseViewController {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var stakingLabel: UILabel!
    @IBOutlet var stakingSubtitleLabel: UILabel!
    @IBOutlet var rewardsLabel: UILabel!
    @IBOutlet var rewardsSubtitleLabel: UILabel!
    @IBOutlet var logoWrapper: UIView!
    @IBOutlet var continueButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        viewModel.didShowInfoScreen()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
    }

    @IBAction
    func continueAction() {
        navigationController?.replaceLast(with: GettingStartedViewController.controller())
    }

    @objc
    static func controller() -> WelcomeToCrowdNodeViewController {
        vc(WelcomeToCrowdNodeViewController.self, from: sb("CrowdNode"))
    }

    private func configureHierarchy() {
        logoWrapper.layer.dw_applyShadow(with: .dw_shadow(), alpha: 0.05, x: 0, y: 0, blur: 10)
        view.backgroundColor = .dw_secondaryBackground()
        
        titleLabel.text = NSLocalizedString("Become part of a Dash Masternode with CrowdNode", comment: "CrowdNode")
        stakingLabel.text = NSLocalizedString("Introducing Staking", comment: "CrowdNode")
        stakingSubtitleLabel.text = NSLocalizedString("Gain rewards from deposits in Dash Masternodes with as little as 0.5 Dash.", comment: "CrowdNode")
        rewardsLabel.text = NSLocalizedString("Get Rewards Instantly", comment: "CrowdNode")
        rewardsSubtitleLabel.text = NSLocalizedString("Receive your share of rewards daily.", comment: "CrowdNode")
        continueButton.setTitle(NSLocalizedString("Continue", comment: ""), for: .normal)
    }
}
