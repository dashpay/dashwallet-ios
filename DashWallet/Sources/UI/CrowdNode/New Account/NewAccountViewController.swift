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
import UIKit

// MARK: - NewAccountViewController

final class NewAccountViewController: UIViewController, UITextViewDelegate {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var explainerLabel1: UILabel!
    @IBOutlet var explainerLabel2: UILabel!
    @IBOutlet var actionButton: DWActionButton!
    @IBOutlet var addressLabel: UILabel!
    @IBOutlet var acceptTermsCheckBox: DWCheckbox!
    @IBOutlet var acceptTermsText: UITextView!
    
    var isLinkingOnlineAccount: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        configureObservers()
    }

    @objc static func controller(online: Bool) -> NewAccountViewController {
        let vc = vc(NewAccountViewController.self, from: sb("CrowdNode"))
        vc.isLinkingOnlineAccount = online
        
        return vc
    }

    @IBAction func continueAction() {
        if isLinkingOnlineAccount {
            let linkingUrl = viewModel.linkOnlineAccount()
            navigationController?.pushViewController(CrowdNodeWebViewController.controller(url: linkingUrl), animated: true)
        }
        else {
            viewModel.signUp()
        }
    }

    @IBAction func copyAddress() {
        UIPasteboard.general.string = addressLabel.text
        view.dw_showInfoHUD(withText: NSLocalizedString("Copied", comment: ""))
    }

    @IBAction func onTermsChecked() {
        actionButton.isEnabled = acceptTermsCheckBox.isOn && viewModel.signUpEnabled
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancellableBag.removeAll()
    }
}

extension NewAccountViewController {
    private func configureHierarchy() {
        definesPresentationContext = true
        view.backgroundColor = UIColor.dw_background()
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance

        configureTermsCheckBox()
        
        if isLinkingOnlineAccount {
            configureForLinkingOnlineAccount()
        } else {
            configureActionButton()
        }
    }

    private func configureActionButton() {
        if viewModel.isInterrupted {
            actionButton.setTitle(NSLocalizedString("Accept Terms Of Use", comment: "CrowdNode"), for: .normal)
        }
        else {
            actionButton.setTitle(NSLocalizedString("Create Account", comment: "CrowdNode"), for: .normal)
        }
    }

    private func configureTermsCheckBox() {
        let baseString = NSMutableAttributedString(string: NSLocalizedString("I agree to CrowdNode", comment: "CrowdNode").description)
        let termsOfUseString = NSMutableAttributedString(string: NSLocalizedString(" Terms of Use ", comment: "CrowdNode").description)
        let andString = NSMutableAttributedString(string: NSLocalizedString("and", comment: "CrowdNode").description)
        let privacyPolicyString = NSMutableAttributedString(string: NSLocalizedString(" Privacy Policy ", comment: "CrowdNode")
            .description)

        termsOfUseString.addAttribute(.link, value: CrowdNode.termsOfUseUrl,
                                      range: NSRange(location: 0, length: termsOfUseString.length))
        privacyPolicyString.addAttribute(.link, value: CrowdNode.privacyPolicyUrl,
                                         range: NSRange(location: 0, length: privacyPolicyString.length))

        baseString.append(termsOfUseString)
        baseString.append(andString)
        baseString.append(privacyPolicyString)

        acceptTermsText.attributedText = baseString
        acceptTermsText.textColor = .label
        acceptTermsText.font = UIFont.dw_regularFont(ofSize: 14)
        acceptTermsCheckBox.style = .square
        acceptTermsCheckBox.isOn = false
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange,
                  interaction: UITextItemInteraction)
        -> Bool {
        UIApplication.shared.open(URL)
        return false
    }
    
    private func configureForLinkingOnlineAccount() {
        titleLabel.text = NSLocalizedString("Link Existing CrowdNode Account", comment: "CrowdNode")
        actionButton.setTitle("Log in to CrowdNode", for: .normal)
        explainerLabel1.text = NSLocalizedString("All transfers to and from CrowdNode from this device will be performed with the below Dash address from this device.", comment: "CrowdNode")
        explainerLabel2.isHidden = true
        explainerLabel2.heightAnchor.constraint(equalToConstant: 0).isActive = true
    }

    private func configureObservers() {
        viewModel.$signUpEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                guard let wSelf = self else { return }
                wSelf.actionButton.isEnabled = wSelf.acceptTermsCheckBox.isOn && isEnabled
            }
            .store(in: &cancellableBag)

        viewModel.$accountAddress
            .receive(on: DispatchQueue.main)
            .assign(to: \.text!, on: addressLabel)
            .store(in: &cancellableBag)

        viewModel.$signUpState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                let isCreating = state == .fundingWallet || state == .acceptingTerms || state == .signingUp

                if isCreating {
                    self?.navigationController?.replaceLast(2, with: AccountCreatingController.controller())
                }
            }
            .store(in: &cancellableBag)
    }
}
