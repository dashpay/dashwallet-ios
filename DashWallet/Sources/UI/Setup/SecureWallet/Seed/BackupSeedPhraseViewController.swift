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

import Foundation

import UIKit

class BackupSeedPhraseViewController: DWPreviewSeedPhraseViewController {

    var shouldCreateNewWalletOnScreenshot: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = NSLocalizedString("Backup Wallet", comment: "A noun. Used as a title.")
        self.actionButton?.isEnabled = false

        self.contentView.displayType = DWSeedPhraseDisplayType.backup

        #if SNAPSHOT
        self.actionButton.accessibilityIdentifier = "seedphrase_continue_button"
        #endif
    }

    override var actionButtonTitle: String {
        return NSLocalizedString("Continue", comment: "")
    }

    @objc override func actionButtonAction(_ sender: Any) {
        // The preview leaves the screen when it has no phrase; never verify
        // an empty one.
        guard let seedPhrase = self.contentView.model else { return }

        let controller = DWVerifySeedPhraseViewController(seedPhrase: seedPhrase)
        controller.delegate = self.delegate
        self.navigationController?.pushViewController(controller, animated: true)
    }

    override func screenshotAlertOKAction() {
        if !self.shouldCreateNewWalletOnScreenshot {
            return
        }

        view.dw_showProgressHUD(withMessage: NSLocalizedString("Deleting Wallet…", comment: "Wallets"))
        model.clearAllWallets()

        SwiftDashSDKWalletWiper.waitForPendingWipe { [weak self] succeeded in
            guard let self else { return }
            self.view.dw_hideProgressHUD()

            guard succeeded else {
                let alert = UIAlertController(
                    title: NSLocalizedString("Couldn’t Delete Wallet", comment: "Wallets"),
                    message: NSLocalizedString(
                        "The wallet is still stored on this device. Please try again.",
                        comment: "Wallets"),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("OK", comment: ""),
                    style: .default))
                self.present(alert, animated: true)
                return
            }

            self.feedbackGenerator.notificationOccurred(.error)

            // nil: the keychain could not be read after the wipe, so no
            // replacement was generated. The phrase on screen belongs to the
            // wallet that was just deleted, and the seed view cannot show
            // nothing — leave this screen (as it does on resign-active) for
            // the backup-info step, whose Show Recovery Phrase / Skip generate
            // the replacement on the next tap, and say why there.
            guard let seedPhrase = self.model.getOrCreateNewWallet() else {
                let navigation = self.navigationController
                navigation?.popViewController(animated: false)
                let alert = UIAlertController(
                    title: nil,
                    message: NSLocalizedString(
                        "Your wallet couldn't be read right now. Please try again.",
                        comment: ""),
                    preferredStyle: .alert)
                alert.addAction(UIAlertAction(
                    title: NSLocalizedString("OK", comment: ""),
                    style: .default))
                (navigation?.topViewController ?? self).present(alert, animated: true)
                return
            }
            self.contentView.updateSeedPhraseModelAnimated(seedPhrase)
            self.contentView.showScreenshotDetectedErrorMessage()
            self.actionButton?.isEnabled = false
        }
    }
}
