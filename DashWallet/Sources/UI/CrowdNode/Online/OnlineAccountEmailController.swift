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
    @IBOutlet var actionButtonBottomConstraint: NSLayoutConstraint!
    
    static func controller() -> OnlineAccountEmailController {
        vc(OnlineAccountEmailController.self, from: sb("CrowdNode"))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureHierarchy()
    }
    
    @IBAction
    func onContinue() {
        self.view.endEditing(true)
    }
    
    private func configureHierarchy() {
        input.placeholder = NSLocalizedString("e.g. johndoe@mail.com", comment: "CrowdNode")
        input.label = NSLocalizedString("Email", comment: "CrowdNode")
        
        NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardShown(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)

        NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardHidden(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc
    private func onKeyboardShown(notification: NSNotification) {
        if let offset = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue.height {
            actionButtonBottomConstraint.constant = offset + 20
        }
    }

    @objc
    private func onKeyboardHidden(_: NSNotification) {
        actionButtonBottomConstraint.constant = 20
    }
}
