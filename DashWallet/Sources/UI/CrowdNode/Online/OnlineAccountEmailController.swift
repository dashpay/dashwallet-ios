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

final class OnlineAccountEmailController: UIViewController {
    private var cancellableBag = Set<AnyCancellable>()
    private let viewModel = CrowdNodeModel.shared

    @IBOutlet var input: OutlinedTextField!
    @IBOutlet var continueButton: DWActionButton!
    @IBOutlet var errorLabel: UILabel!
    @IBOutlet var actionButtonBottomConstraint: NSLayoutConstraint!
    
    private var isInProgress: Bool = false {
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

extension OnlineAccountEmailController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        validateAndSign()
        return true
    }
    
    private func configureEmailInput() {
        input.label = NSLocalizedString("Email", comment: "CrowdNode")
        input.text = viewModel.emailForAccount
        input.placeholder = NSLocalizedString("e.g. johndoe@mail.com", comment: "CrowdNode")
        input.textContentType = .emailAddress
        input.keyboardType = .emailAddress
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        input.spellCheckingType = .no
        input.delegate = self
        input.addTarget(self, action: #selector(onInputTextChanged), for: .editingChanged)
    }
    
    @objc
    private func onInputTextChanged() {
        input.isError = false
        errorLabel.isHidden = true
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
            input.isError = false
            errorLabel.isHidden = true
            
            Task {
                do {
                    let isSent = try await viewModel.signAndSendEmail(email: input.text!.trimmingCharacters(in: .whitespacesAndNewlines))
                    
                    if !isSent {
                        isInProgress = false
                    }
                } catch {
                    isInProgress = false
                    errorLabel.isHidden = false
                    errorLabel.text = error.localizedDescription
                }
            }
        } else {
            input.isError = true
            errorLabel.isHidden = false
            errorLabel.text = NSLocalizedString("Invalid Email", comment: "CrowdNode Online")
        }
    }
    
    private func transitionSignUpState(_ state: CrowdNode.OnlineAccountState) {
        switch state {
        case .creating:
            self.view.endEditing(true)
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
