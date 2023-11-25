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
    @IBOutlet private var continueButton: UIButton!
    
    @objc
    static func controller() -> VerifyIdenityViewController {
        vc(VerifyIdenityViewController.self, from: sb("UsernameRequests"))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
    }
    
    @IBAction
    func continueAction() {
        if linkField.text.count > 75 {
            linkField.errorMessage = NSLocalizedString("Maximum 75 characters", comment: "Usernames")
            return
        }
        
        if let url = URL(string: linkField.text), url.scheme != nil {
            let vc = ConfirmRequestViewController.controller(withProve: url)
            vc.onResult = { result in
                if result {
                    self.navigationController?.popToRootViewController(animated: true)
                }
            }
            present(vc, animated: true)
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
    }
    
    private func updateView() {
        continueButton.isEnabled = !linkField.text.isEmpty
        linkField.errorMessage = nil
    }
}
