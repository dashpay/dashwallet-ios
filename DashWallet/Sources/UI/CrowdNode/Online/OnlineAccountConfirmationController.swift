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

// MARK: - OnlineAccountConfirmationController

final class OnlineAccountConfirmationController: BaseViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel = CrowdNode.shared
    private var paymentRequest: DSPaymentRequest {
        let chain = DWEnvironment.sharedInstance().currentChain
        let paymentRequest = DSPaymentRequest(string: viewModel.accountAddress, on: chain)
        paymentRequest.amount = CrowdNode.apiConfirmationDashAmount
        return paymentRequest
    }

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var howToConfirmLabel: UILabel!
    @IBOutlet var primaryAddressTitle: UILabel!
    @IBOutlet var primaryAddressLabel: UILabel!
    @IBOutlet var addressTitle: UILabel!
    @IBOutlet var addressLabel: UILabel!
    @IBOutlet var infoLabel: UILabel!
    @IBOutlet var info2Label: UILabel!
    @IBOutlet var documentationLinkButton: UIStackView!
    @IBOutlet var qrButton: UIButton!
    @IBOutlet var shareButton: UIButton!
    @IBOutlet var attentionBox: UIView!
    @IBOutlet var attentionLabel: UILabel!

    static func controller() -> OnlineAccountConfirmationController {
        vc(OnlineAccountConfirmationController.self, from: sb("CrowdNode"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureObservers()
    }

    @IBAction
    func closeAction() {
        dismiss(animated: true)
    }

    @IBAction
    func copyPrimaryAddressAction() {
        UIPasteboard.general.string = viewModel.primaryAddress
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }

    @IBAction
    func copyAddressAction() {
        UIPasteboard.general.string = viewModel.accountAddress
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }

    @IBAction
    func showQrAction() {
        present(ConfirmationTransactionQRController.controller(paymentRequest), animated: true)
    }

    @IBAction
    func shareAction() {
        let sharedObjects: [AnyObject] = [paymentRequest.url as AnyObject]
        let activityViewController = UIActivityViewController(activityItems: sharedObjects, applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = view
        present(activityViewController, animated: true, completion: nil)
    }

    @objc
    func onDocumentationLinkTapped() {
        UIApplication.shared.open(URL(string: CrowdNode.howToVerifyUrl)!)
    }
}

extension OnlineAccountConfirmationController {
    private func configureHierarchy() {
        view.backgroundColor = .dw_secondaryBackground()

        titleLabel.text = NSLocalizedString("Verify your API Dash address", comment: "CrowdNode")
        howToConfirmLabel.text = NSLocalizedString("How to confirm your API Dash address", comment: "CrowdNode")
        primaryAddressTitle.text = NSLocalizedString("Primary Dash address", comment: "CrowdNode")
        info2Label.text = NSLocalizedString("to the Dash address designated for your CrowdNode account in the Dash Wallet on this device", comment: "CrowdNode")
        primaryAddressLabel.text = viewModel.primaryAddress
        addressTitle.text = NSLocalizedString("Dash address", comment: "CrowdNode")
        addressLabel.text = viewModel.accountAddress
        qrButton.setTitle(NSLocalizedString("Show QR", comment: "CrowdNode"), for: .normal)
        qrButton.titleLabel?.font = UIFont.dw_mediumFont(ofSize: 13)
        qrButton.setTitle(NSLocalizedString("Share", comment: "CrowdNode"), for: .normal)
        shareButton.titleLabel?.font = UIFont.dw_mediumFont(ofSize: 13)
        attentionBox.layer.borderWidth = 1
        attentionBox.layer.borderColor = UIColor.systemYellow.cgColor
        attentionLabel.text = NSLocalizedString("We will automatically detect this transaction and transfer the same amount to your CrowdNode account. After that you will be able to make deposits and withdrawals in Dash Wallet on this device.", comment: "CrowdNode")
        
        let confirmationAmount = CrowdNode.apiConfirmationDashAmount.formattedDashAmount
        infoLabel.text = String
            .localizedStringWithFormat(NSLocalizedString("Send %@ from your primary Dash address that you currently use for your CrowdNode account", comment: "CrowdNode Confirm"),
                                       confirmationAmount)

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(onDocumentationLinkTapped))
        documentationLinkButton.addGestureRecognizer(tapGestureRecognizer)
    }

    private func configureObservers() {
        viewModel.$onlineAccountState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if state == .done {
                    self?.presentingViewController?.dismiss(animated: true)
                }
            }
            .store(in: &cancellableBag)

        viewModel.$apiError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if error != nil {
                    self?.presentingViewController?.dismiss(animated: true)
                }
            }
            .store(in: &cancellableBag)
    }
}
