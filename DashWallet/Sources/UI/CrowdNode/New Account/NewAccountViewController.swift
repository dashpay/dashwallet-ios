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

final class NewAccountViewController: UIViewController, UITextViewDelegate {
    private let viewModel = CrowdNodeModel.shared
    private var cancellableBag = Set<AnyCancellable>()

    @IBOutlet var actionButton: DWActionButton!
    @IBOutlet var addressLabel: UILabel!
    @IBOutlet var acceptTermsCheckBox: DWCheckbox!
    @IBOutlet var acceptTermsText: UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()

        configureHierarchy()
        configureObservers()
    }

    @objc static func controller() -> NewAccountViewController {
        let storyboard = UIStoryboard(name: "CrowdNode", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "NewAccountViewController") as! NewAccountViewController
        return vc
    }

    @IBAction func continueAction() {
        viewModel.signUp()
    }

    @IBAction func copyAddress() {
        UIPasteboard.general.string = addressLabel.text
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

        configureActionButton()
        configureAccountAddress()
        configureTermsCheckBox()
    }

    private func configureActionButton() {
        if viewModel.isInterrupted {
            actionButton.setTitle(NSLocalizedString("Accept Terms Of Use", comment: ""), for: .normal)
        }
        else {
            actionButton.setTitle(NSLocalizedString("Create Account", comment: ""), for: .normal)
        }
    }

    private func configureAccountAddress() {
        let gradientMaskLayer = CAGradientLayer()
        gradientMaskLayer.frame = addressLabel.bounds
        gradientMaskLayer.colors = [UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor, UIColor.clear.cgColor]
        gradientMaskLayer.locations = [0, 0.7, 0.85, 1]
        gradientMaskLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientMaskLayer.endPoint = CGPoint(x: 1, y: 0.5)
        addressLabel.layer.mask = gradientMaskLayer
    }

    private func configureTermsCheckBox() {
        let baseString = NSMutableAttributedString(string: NSLocalizedString("I agree to CrowdNode", comment: "").description)
        let termsOfUseString = NSMutableAttributedString(string: NSLocalizedString(" Terms of Use ", comment: "").description)
        let andString = NSMutableAttributedString(string: NSLocalizedString("and", comment: "").description)
        let privacyPolicyString = NSMutableAttributedString(string: NSLocalizedString(" Privacy Policy ", comment: "").description)

        termsOfUseString.addAttribute(.link, value: CrowdNodeConstants.termsOfUseUrl, range: NSRange(location: 0, length: termsOfUseString.length))
        privacyPolicyString.addAttribute(.link, value: CrowdNodeConstants.privacyPolicyUrl, range: NSRange(location: 0, length: privacyPolicyString.length))

        baseString.append(termsOfUseString)
        baseString.append(andString)
        baseString.append(privacyPolicyString)

        acceptTermsText.attributedText = baseString
        acceptTermsText.font = UIFont.dw_regularFont(ofSize: 14)
        acceptTermsCheckBox.style = .square
        acceptTermsCheckBox.isOn = false
    }

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        UIApplication.shared.open(URL)
        return false
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
