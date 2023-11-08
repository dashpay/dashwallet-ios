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

final class StakingInfoDialogController: UIViewController {
    private let viewModel = CrowdNode.shared

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var benefitsLabel: UILabel!
    @IBOutlet var poolTitle: UILabel!
    @IBOutlet var poolDescription: UILabel!
    @IBOutlet var minimumDepositTitle: UILabel!
    @IBOutlet var rewardsTitle: UILabel!
    @IBOutlet var rewardsDescription: UILabel!
    @IBOutlet var leavingTitle: UILabel!
    @IBOutlet var leavingDescription: UILabel!
    @IBOutlet var leavingDescription2: UILabel!
    @IBOutlet var crowdnodeApyLabel: UILabel!
    @IBOutlet var apyDescription: UILabel!
    @IBOutlet var addressTitle: UILabel!
    @IBOutlet var addressDescription: UILabel!
    
    @IBOutlet var masternodeApyLabel: UILabel!
    @IBOutlet var minimumDepositLabel: UILabel!
    @IBOutlet var addressLabelTitle: UILabel!
    @IBOutlet var addressLabel: UILabel!

    static func controller() -> StakingInfoDialogController {
        vc(StakingInfoDialogController.self, from: sb("CrowdNode"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }

    @IBAction
    func closeAction() {
        dismiss(animated: true)
    }

    @IBAction
    func copyAddressAction() {
        UIPasteboard.general.string = viewModel.accountAddress
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }

    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        titleLabel.text = NSLocalizedString("How CrowdNode staking works", comment: "CrowdNode")
        subtitleLabel.text = NSLocalizedString("TThe Dash Network is driven by a number of Masternodes which are an essential part of facilitating payments.", comment: "CrowdNode")
        benefitsLabel.text = NSLocalizedString("CrowdNode benefits", comment: "CrowdNode")
        poolTitle.text = NSLocalizedString("Joining the pool", comment: "CrowdNode")
        poolDescription.text = NSLocalizedString("As most people do not have exactly 1000 Dash at hand, Crowdnode has made a service where, by pooling deposits from members, they can achieve the benefits of owning a Masternode.", comment: "CrowdNode")
        minimumDepositTitle.text = NSLocalizedString("First minimum deposit", comment: "CrowdNode")
        
        rewardsTitle.text = NSLocalizedString("Receiving rewards", comment: "CrowdNode")
        rewardsDescription.text = NSLocalizedString("You will receive fractional payments automatically and they will by default be reinvested, however, it is also easy to set up automatic withdrawals to receive recurring payouts.", comment: "CrowdNode")
        
        leavingTitle.text = NSLocalizedString("Leaving the pool", comment: "CrowdNode")
        leavingDescription.text = NSLocalizedString("Members are free to leave the pool and can most often leave immediately.", comment: "CrowdNode")
        leavingDescription2.text = NSLocalizedString("In case of larger withdrawals CrowdNode will pay withdrawals within two weeks. This is due to their security protocols and will most often be handled much faster.", comment: "CrowdNode")
        
        apyDescription.text = NSLocalizedString("This represents the current Annual Percentage Yield of a full Masternode less the 15% CrowdNode fee. It is not a guaranteed rate of return and may go up or down based on the size of the CrowdNode pools and the Dash price.", comment: "CrowdNode")
        
        addressTitle.text = NSLocalizedString("Connected Dash address", comment: "CrowdNode")
        addressDescription.text = NSLocalizedString("Here is a Dash address designated for your CrowdNode account in the Dash Wallet on this device", comment: "CrowdNode")
        
        addressLabelTitle.text = NSLocalizedString("Dash address", comment: "")
        
        addressLabel.text = viewModel.accountAddress
        let minimumDeposit = CrowdNode.minimumDeposit.formattedDashAmount
        minimumDepositLabel.text = String.localizedStringWithFormat(NSLocalizedString("You only need %@ to join the pool.", comment: "CrowdNode"), minimumDeposit)

        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.multiplier = 1
        
        masternodeApyLabel.text = String
            .localizedStringWithFormat(NSLocalizedString("A Masternode needs 1000 Dash as collateral and each Masternode is currently rewarded approximately %@ per year.",
                                                         comment: "CrowdNode"),
                                       formatter.string(for: viewModel.masternodeAPY)!)
        crowdnodeApyLabel.text = String.localizedStringWithFormat(NSLocalizedString("Current APY is %@", comment: "CrowdNode"), formatter.string(for: viewModel.crowdnodeAPY)!)
    }
}
