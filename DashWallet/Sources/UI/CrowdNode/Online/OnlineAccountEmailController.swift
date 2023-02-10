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

final class OnlineAccountEmailController: UIViewController {
    private let viewModel = CrowdNode.shared

    @IBOutlet var input: OutlinedTextField!
    @IBOutlet var continueButton: UIButton!
    @IBOutlet var errorLabel: UILabel!
    @IBOutlet var actionButtonBottomConstraint: NSLayoutConstraint!
    
    static func controller() -> OnlineAccountEmailController {
        vc(OnlineAccountEmailController.self, from: sb("CrowdNode"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        input.becomeFirstResponder()
    }
    
    @IBAction
    func onContinue() {
        if isEmail(text: input.text) {
            input.isError = false
            errorLabel.isHidden = true
            self.view.endEditing(true)
        } else {
            input.isError = true
            errorLabel.isHidden = false
        }
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
}

extension OnlineAccountEmailController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onContinue()
        return true
    }
    
    private func configureEmailInput() {
        input.label = NSLocalizedString("Email", comment: "CrowdNode")
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
