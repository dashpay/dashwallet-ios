//
//  Created by Andrew Podkovyrin
//  Copyright © 2019 Dash Core Group. All rights reserved.
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

import UIKit

extension HomeViewController: DWRecoverViewControllerDelegate {
    func performJailbreakCheck() {
        guard UIApplication.isJailbroken else {
            return
        }

        let title = NSLocalizedString("WARNING", comment: "")
        var message: String?
        var mainAction: UIAlertAction?

        if !model.isWalletEmpty {
            message = NSLocalizedString("DEVICE SECURITY COMPROMISED\nAny 'jailbreak' app can access any other app's keychain data (and steal your Dash). Wipe this wallet immediately and restore on a secure device.", comment: "")
            mainAction = UIAlertAction(title: NSLocalizedString("Wipe", comment: ""), style: .destructive) { [weak self] action in
                self?.wipeWallet()
            }
        } else {
            message = NSLocalizedString("DEVICE SECURITY COMPROMISED\nAny 'jailbreak' app can access any other app's keychain data (and steal your Dash).", comment: "")
            mainAction = UIAlertAction(title: NSLocalizedString("Close App", comment: ""), style: .default) { action in
                NotificationCenter.default.post(name: NSNotification.Name.DSApplicationTerminationRequest, object: nil)
            }
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let ignoreAction = UIAlertAction(title: NSLocalizedString("Ignore", comment: ""), style: .cancel, handler: nil)
        
        if let mainAction = mainAction {
            alert.addAction(mainAction)
        }
        alert.addAction(ignoreAction)
        
        present(alert, animated: true, completion: nil)
    }

    func wipeWallet() {
        let controller = DWRecoverViewController()
        controller.action = .wipe
        controller.delegate = self
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(recoverCancelButtonAction(_:)))
        controller.navigationItem.leftBarButtonItem = cancelButton

        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true, completion: nil)
    }

    // MARK: - DWRecoverViewControllerDelegate

    func recoverViewControllerDidRecoverWallet(_ controller: DWRecoverViewController, recover recoverCommand: DWRecoverWalletCommand) {
        assertionFailure("Inconsistent state")
        dismiss(animated: true, completion: nil)
    }

    func recoverViewControllerDidWipe(_ controller: DWRecoverViewController) {
        dismiss(animated: true) { [weak self] in
            self?.delegate?.didWipeWallet()
        }
    }

    @objc func recoverCancelButtonAction(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }
}
