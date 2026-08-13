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
    private var hasAppeared = false

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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        dw_endExclusiveUserAction()
        if hasAppeared {
            actionButton?.isEnabled = true
        }
        hasAppeared = true
    }

    @objc override func actionButtonAction(_ sender: Any) {
        guard dw_beginExclusiveUserAction() else { return }
        actionButton?.isEnabled = false

        let seedPhrase = self.contentView.model

        let controller = DWVerifySeedPhraseViewController(seedPhrase: seedPhrase!)
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

            let seedPhrase = self.model.getOrCreateNewWallet()
            self.contentView.updateSeedPhraseModelAnimated(seedPhrase)
            self.contentView.showScreenshotDetectedErrorMessage()
            self.actionButton?.isEnabled = false
        }
    }
}
