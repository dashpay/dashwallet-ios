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

    @IBOutlet var masternodeApyLabel: UILabel!
    @IBOutlet var crowdnodeApyLabel: UILabel!
    @IBOutlet var minimumDepositLabel: UILabel!
    @IBOutlet var addressLabel: UILabel!

    static func controller() -> StakingInfoDialogController {
        vc(StakingInfoDialogController.self, from: sb("CrowdNode"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }

    @IBAction func closeAction() {
        dismiss(animated: true)
    }

    @IBAction func copyAddressAction() {
        UIPasteboard.general.string = CrowdNode.shared.accountAddress
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }

    private func configureHierarchy() {
        addressLabel.text = CrowdNode.shared.accountAddress
        let minimumDeposit = DSPriceManager.sharedInstance().string(forDashAmount: Int64(CrowdNode.minimumDeposit))!
        minimumDepositLabel.text = String.localizedStringWithFormat(NSLocalizedString("You only need %@ to join the pool.", comment: "CrowdNode"), minimumDeposit)

        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        masternodeApyLabel.text = String
            .localizedStringWithFormat(NSLocalizedString("A Masternode needs 1000 Dash as collateral and each Masternode is currently rewarded approximately %@ per year.",
                                                         comment: "CrowdNode"),
                                       formatter.string(for: viewModel.masternodeAPY)!)
        crowdnodeApyLabel.text = String.localizedStringWithFormat(NSLocalizedString("Current APY is %@", comment: "CrowdNode"), formatter.string(for: viewModel.crowdnodeAPY)!)
    }
}
