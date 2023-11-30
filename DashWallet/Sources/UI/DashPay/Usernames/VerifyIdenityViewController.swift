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

class VerifyIdenityViewController: UIViewController {
    private let viewModel = RequestUsernameViewModel.shared
    
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var subtitleLabel: UILabel!
    @IBOutlet private var copyBoxLabel: UILabel!
    @IBOutlet private var copyBoxText: UILabel!
    @IBOutlet private var copyContainer: UIView!
    @IBOutlet private var proveTitle: UILabel!
    @IBOutlet private var proveDescription: UILabel!
    @IBOutlet private var linkField: DashInputField!
    @IBOutlet private var continueButton: ActionButton!
    
    @objc
    static func controller() -> VerifyIdenityViewController {
        vc(VerifyIdenityViewController.self, from: sb("UsernameRequests"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ka_startObservingKeyboardNotifications()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ka_stopObservingKeyboardNotifications()
    }
    
    @IBAction
    func continueAction() {
        if linkField.text.count > 75 {
            linkField.errorMessage = NSLocalizedString("Maximum 75 characters", comment: "Usernames")
            return
        }
        
        if let url = URL(string: linkField.text), url.scheme != nil {
            if viewModel.currentUsernameRequest == nil {
                confirmUsernameRequest(link: url)
            } else {
                viewModel.updateRequest(with: url)
                self.navigationController?.popViewController(animated: true)
            }
        } else {
            linkField.errorMessage = NSLocalizedString("Not a valid URL", comment: "Usernames")
        }
    }
    
    @IBAction
    func sharePost() {
        if let text = copyBoxText.text {
            let activityViewController = UIActivityViewController(activityItems: [text], applicationActivities: nil)
            activityViewController.excludedActivityTypes = [UIActivity.ActivityType.airDrop]
            present(activityViewController, animated: true, completion: nil)
        }
    }
}

extension VerifyIdenityViewController {
    private func configureLayout() {
        titleLabel.text = NSLocalizedString("Verify your identity", comment: "Usernames")
        subtitleLabel.text = NSLocalizedString("The link you send will be visible to all of the Dash network.", comment: "Usernames")
        
        copyBoxLabel.text = NSLocalizedString("Example post", comment: "Usernames")
        copyBoxText.text = String.localizedStringWithFormat(NSLocalizedString("Please vote to approve my requested Dash username - %@", comment: "Usernames"), viewModel.enteredUsername)
        
        proveTitle.text = NSLocalizedString("Prove your identity", comment: "Usernames")
        proveDescription.text = NSLocalizedString("Make a post with the text above (or something similar) on a well known social media or messaging platform to verify that you are the original owner of the requested username and paste a link to the post bellow", comment: "Usernames")
        
        linkField.autocorrectionType = .no
        linkField.spellCheckingType = .no
        linkField.autocapitalizationType = .none
        linkField.textDidChange = { [weak self] text in
            self?.updateView()
        }
        linkField.isEnabled = true
        linkField.placeholder = NSLocalizedString("Paste the link", comment: "Usernames")
        linkField.translatesAutoresizingMaskIntoConstraints = false
        
        continueButton.setTitle(NSLocalizedString("Verify", comment: ""), for: .normal)
        
        view.keyboardLayoutGuide.topAnchor.constraint(equalToSystemSpacingBelow: continueButton.bottomAnchor, multiplier: 1.0).isActive = true
    }
    
    private func updateView() {
        continueButton.isEnabled = !linkField.text.isEmpty
        linkField.errorMessage = nil
    }
}

extension VerifyIdenityViewController {
    func confirmUsernameRequest(link: URL?) {
        if viewModel.shouldRequestPayment {
            let vc = ConfirmRequestViewController.controller(withProve: link)
            vc.onResult = { result in
                if result {
                    self.navigationController?.popToRootViewController(animated: true)
                }
            }
            present(vc, animated: true)
        } else {
            Task {
                continueButton.showActivityIndicator()
                let result = await self.viewModel.submitUsernameRequest(withProve: nil)
                continueButton.hideActivityIndicator()
                
                if result {
                    self.viewModel.onFlowComplete(withResult: true)
                    self.navigationController?.popToRootViewController(animated: true)
                } else {
                    self.showError()
                }
            }
        }
    }
    
    private func showError() {
        let alert = UIAlertController(title: NSLocalizedString("Something went wrong", comment: ""), message: NSLocalizedString("There was a network error, you can try again at no extra cost", comment: "Usernames"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Try Again", comment: ""), style: .default, handler: { [weak self] _ in
            self?.confirmUsernameRequest(link: URL(string: self?.linkField.text ?? ""))
        }))
        let cancelAction = UIAlertAction(title: NSLocalizedString("Close", comment: ""), style: .cancel)
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }
}

extension VerifyIdenityViewController {
    override func ka_keyboardShowOrHideAnimation(withHeight height: CGFloat, animationDuration: TimeInterval,
                                                 animationCurve: UIView.AnimationCurve) {
        if height == 0 {
            // Keyboard hidden, lower layout
            view.frame.origin.y = 0
        } else {
            let diff = height - view.frame.height + linkField.frame.maxY + continueButton.frame.height
            // Raise keyboard a bit. Accounts for not enough space on small screens
            view.frame.origin.y = view.frame.origin.y - 50 - max(diff, 0)
        }
    }
}
