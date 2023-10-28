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

// MARK: - OnlineAccountEmailController

final class OnlineAccountEmailController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel = CrowdNodeModel.shared

    @IBOutlet var input: DashInputField!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var subtitleLabel: UILabel!
    @IBOutlet var continueButton: ActionButton!
    @IBOutlet var actionButtonBottomConstraint: NSLayoutConstraint!

    private var isInProgress = false {
        didSet {
            if isInProgress {
                continueButton.showActivityIndicator()
                input.isEnabled = false
            } else {
                continueButton.hideActivityIndicator()
                input.isEnabled = true
            }
        }
    }

    static func controller() -> OnlineAccountEmailController {
        vc(OnlineAccountEmailController.self, from: sb("CrowdNode"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
        configureObservers()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if viewModel.onlineAccountState != .creating {
            input.becomeFirstResponder()
        }
    }

    @IBAction
    func onContinue() {
        validateAndSign()
    }

    private func configureHierarchy() {
        configureEmailInput()
        
        titleLabel.text = NSLocalizedString("Create an online CrowdNode account", comment: "CrowdNode")
        subtitleLabel.text = NSLocalizedString("Please note that the email is not saved by the Dash Wallet and is only sent to CrowdNode", comment: "CrowdNode")
        continueButton.setTitle(NSLocalizedString("Continue", comment: ""), for: .normal)

        NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardShown(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardHidden(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc
    private func onKeyboardShown(notification: NSNotification) {
        if let offset = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height {
            actionButtonBottomConstraint.constant = offset + 10
        }
    }

    @objc
    private func onKeyboardHidden(_: NSNotification) {
        actionButtonBottomConstraint.constant = 20
    }

    private func configureObservers() {
        viewModel.$onlineAccountState
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.transitionSignUpState(state)
            }
            .store(in: &cancellableBag)

        viewModel.$error
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                if error is CrowdNode.Error {
                    self?.viewModel.clearError()
                    self?.navigationController?.toErrorScreen(error: error as! CrowdNode.Error)
                }
            }
            .store(in: &cancellableBag)
    }
}

// MARK: UITextViewDelegate

extension OnlineAccountEmailController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let range = text.rangeOfCharacter(from: .newlines) else {
            return true
        }

        input.resignFirstResponder()
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        validateAndSign()
        return true
    }

    private func configureEmailInput() {
        input.placeholder = NSLocalizedString("Email", comment: "CrowdNode")
        input.text = viewModel.emailForAccount
        input.placeholder = NSLocalizedString("e.g. johndoe@mail.com", comment: "CrowdNode")
        input.textContentType = .emailAddress
        input.keyboardType = .emailAddress
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        input.spellCheckingType = .no
        input.delegate = self
        input.textDidChange = { [weak self] _ in
            self?.onInputTextChanged()
        }
    }

    @objc
    private func onInputTextChanged() {
        continueButton.isEnabled = isEmail(text: input.text)
    }

    private func isEmail(text: String?) -> Bool {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format:"SELF MATCHES %@", regex)

        return predicate.evaluate(with: trimmed)
    }
}

extension OnlineAccountEmailController {
    private func validateAndSign() {
        if isEmail(text: input.text) {
            isInProgress = true

            Task {
                do {
                    let isSent = try await viewModel.signAndSendEmail(email: input.text.trimmingCharacters(in: .whitespacesAndNewlines))

                    if !isSent {
                        isInProgress = false
                    }
                } catch {
                    isInProgress = false
                    input.errorMessage = error.localizedDescription
                }
            }
        } else {
            input.errorMessage = NSLocalizedString("Invalid Email", comment: "CrowdNode Online")
        }
    }

    private func transitionSignUpState(_ state: CrowdNode.OnlineAccountState) {
        switch state {
        case .creating:
            view.endEditing(true)
            isInProgress = true
        case .signingUp:
            let signupUrl = CrowdNode.profileUrl
            navigationController?.replaceLast(with: CrowdNodeWebViewController.controller(url: URL(string: signupUrl)!, email: viewModel.emailForAccount))
            isInProgress = false
        default:
            isInProgress = false
        }
    }
}
