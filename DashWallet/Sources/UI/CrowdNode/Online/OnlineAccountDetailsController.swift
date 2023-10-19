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

final class OnlineAccountDetailsController: BaseViewController {
    private let viewModel = CrowdNodeModel.shared

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var primaryAddressTitle: UILabel!
    @IBOutlet var primaryAddressLabel: UILabel!
    @IBOutlet var subtitle2Label: UILabel!
    @IBOutlet var addressTitle: UILabel!
    @IBOutlet var addressLabel: UILabel!

    static func controller() -> OnlineAccountDetailsController {
        vc(OnlineAccountDetailsController.self, from: sb("CrowdNode"))
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

    @IBAction
    func copyPrimaryAddressAction() {
        UIPasteboard.general.string = viewModel.primaryAddress
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }

    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        primaryAddressLabel.text = viewModel.primaryAddress
        addressLabel.text = viewModel.accountAddress
        titleLabel.text = NSLocalizedString("Information about your online account", comment: "CrowdNode")
        subtitleLabel.text = NSLocalizedString("Your primary Dash address that you currently use for your CrowdNode account", comment: "CrowdNode")
        primaryAddressTitle.text = NSLocalizedString("Primary Dash address", comment: "CrowdNode")
        subtitle2Label.text = NSLocalizedString("Dash address designated for your CrowdNode account in the Dash Wallet on this device ", comment: "CrowdNode")
        addressTitle.text = NSLocalizedString("Dash address", comment: "")
    }
}
