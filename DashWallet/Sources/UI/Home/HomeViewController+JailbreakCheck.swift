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

extension HomeViewController {
    /// The jailbreak signal is a heuristic, so this only informs — wiping stays
    /// behind Security → Reset Wallet, which gates it on the recovery phrase.
    func performJailbreakCheck() {
        guard UIApplication.isJailbroken else {
            return
        }

        let title = NSLocalizedString("WARNING", comment: "")
        let message: String
        var mainAction: UIAlertAction?

        if !model.isWalletEmpty {
            message = NSLocalizedString("DEVICE SECURITY COMPROMISED\nAny 'jailbreak' app can access any other app's keychain data (and steal your Dash). Move your funds to a wallet on a secure device, then reset this wallet using Reset Wallet in the Security menu.", comment: "")
        } else {
            message = NSLocalizedString("DEVICE SECURITY COMPROMISED\nAny 'jailbreak' app can access any other app's keychain data (and steal your Dash).", comment: "")
            mainAction = UIAlertAction(title: NSLocalizedString("Close App", comment: ""), style: .default) { action in
                NotificationCenter.default.post(name: .applicationTerminationRequest, object: nil)
            }
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if let mainAction = mainAction {
            alert.addAction(mainAction)
            alert.addAction(UIAlertAction(title: NSLocalizedString("Ignore", comment: ""), style: .cancel, handler: nil))
        } else {
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .cancel, handler: nil))
        }

        present(alert, animated: true, completion: nil)
    }
}
