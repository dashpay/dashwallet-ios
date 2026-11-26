//
//  Created by Dash Core Group
//  Copyright © 2026 Dash Core Group. All rights reserved.
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

/// Hosts `RecoveryPhraseView`. Backing up, Continue goes on to verify the
/// phrase; viewing it again, Done hands back to the delegate. Either way the
/// screen warns on a screenshot and closes when the app leaves the
/// foreground, so the phrase is not left on screen.
final class RecoveryPhraseViewController: SetupScreenViewController {
    weak var delegate: DWSecureWalletDelegate?

    private let viewModel: RecoveryPhraseViewModel
    private let feedback = UINotificationFeedbackGenerator()

    init(model: DWPreviewSeedPhraseModel, mode: RecoveryPhraseViewModel.Mode) {
        viewModel = RecoveryPhraseViewModel(mode: mode, seedPhrase: model.getOrCreateNewWallet())
        super.init(nibName: nil, bundle: nil)

        switch mode {
        case .backup:
            title = String(localized: "Backup Wallet", comment: "A noun. Used as a title.")
        case .preview:
            title = String(localized: "Recovery Phrase", comment: "")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(named: "SecondaryBackgroundColor")
        embedScreen(RecoveryPhraseView(
            viewModel: viewModel,
            onContinue: { [weak self] in self?.continueAction() },
            onWhyNoScreenshot: { [weak self] in self?.showWhyNoScreenshot() }
        ))

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(userDidTakeScreenshot),
                                               name: UIApplication.userDidTakeScreenshotNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
    }

    // MARK: Actions

    private func continueAction() {
        switch viewModel.mode {
        case .backup:
            let controller = VerifyRecoveryPhraseViewController(seedPhrase: viewModel.seedPhrase)
            controller.delegate = delegate
            navigationController?.pushViewController(controller, animated: true)
        case .preview:
            delegate?.secureWalletRoutineDidCancel(self)
        }
    }

    private func showWhyNoScreenshot() {
        let controller = BackupInfoViewController.controller(with: .setup)
        controller.isAllActionHidden = true
        controller.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: Notifications

    @objc
    private func userDidTakeScreenshot() {
        feedback.notificationOccurred(.warning)
        showModalDialog(
            style: .warning,
            icon: .custom("icon_screenshot_warning"),
            heading: String(localized: "WARNING", comment: ""),
            textBlock1: String(localized: "Screenshots are visible to other apps and devices. Generate a new recovery phrase and keep it secret.",
                               comment: ""),
            positiveButtonText: String(localized: "OK", comment: "")
        )
    }

    @objc
    private func applicationWillResignActive() {
        navigationController?.popViewController(animated: false)
    }
}
