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

final class OnlineAccountConfirmationController: UIViewController {
    private let viewModel = CrowdNode.shared
    private var paymentRequest: DSPaymentRequest {
        let chain = DWEnvironment.sharedInstance().currentChain
        let paymentRequest = DSPaymentRequest.init(string: viewModel.accountAddress, on: chain)
        paymentRequest.amount = CrowdNode.apiConfirmationDashAmount
        return paymentRequest
    }

    @IBOutlet var primaryAddressLabel: UILabel!
    @IBOutlet var addressLabel: UILabel!
    @IBOutlet var infoLabel: UILabel!
    @IBOutlet var documentationLinkButton: UIStackView!
    @IBOutlet var qrButton: UIButton!
    @IBOutlet var shareButton: UIButton!
    @IBOutlet var attentionBox: UIView!

    static func controller() -> OnlineAccountConfirmationController {
        vc(OnlineAccountConfirmationController.self, from: sb("CrowdNode"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }

    @IBAction func closeAction() {
        dismiss(animated: true)
    }

    @IBAction func copyPrimaryAddressAction() {
        UIPasteboard.general.string = viewModel.primaryAddress
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }
    
    @IBAction func copyAddressAction() {
        UIPasteboard.general.string = viewModel.accountAddress
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }
    
    @IBAction func showQrAction() {
        present(ConfirmationTransactionQRController.controller(paymentRequest), animated: true)
    }
    
    @IBAction func shareAction() {
        let sharedObjects: [AnyObject] = [paymentRequest.url as AnyObject]
        let activityViewController = UIActivityViewController(activityItems: sharedObjects, applicationActivities: nil)
        activityViewController.popoverPresentationController?.sourceView = self.view
        self.present(activityViewController, animated: true, completion: nil)
    }

    private func configureHierarchy() {
        primaryAddressLabel.text = viewModel.primaryAddress
        addressLabel.text = viewModel.accountAddress
        qrButton.titleLabel?.font = UIFont.dw_mediumFont(ofSize: 13)
        shareButton.titleLabel?.font = UIFont.dw_mediumFont(ofSize: 13)
        attentionBox.layer.borderWidth = 1
        attentionBox.layer.borderColor = UIColor.systemYellow.cgColor
        
        let confirmationAmount = CrowdNode.apiConfirmationDashAmount.formattedDashAmount
        infoLabel.text = String.localizedStringWithFormat(NSLocalizedString("Send %@ from your primary Dash address that you currently use for your CrowdNode account", comment: "CrowdNode Confirm"), confirmationAmount)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(onDocumentationLinkTapped))
        documentationLinkButton.addGestureRecognizer(tapGestureRecognizer)
    }
    
    @objc func onDocumentationLinkTapped() {
        UIApplication.shared.open(URL(string: CrowdNode.howToVerifyUrl)!)
    }
}
