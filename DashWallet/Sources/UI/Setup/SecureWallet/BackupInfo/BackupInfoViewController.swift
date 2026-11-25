//
//  Created by PT
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

import UIKit

// MARK: - SecureWalletInfoType

@objc(DWSecureWalletInfoType)
enum SecureWalletInfoType: Int {
    @objc(DWSecureWalletInfoType_Setup)
    case setup

    @objc(DWSecureWalletInfoType_Reminder)
    case reminder
}

// MARK: - BackupInfoViewControllerDelegate

@objc(DWBackupInfoViewControllerDelegate)
protocol BackupInfoViewControllerDelegate: DWSecureWalletDelegate { }

// MARK: - BackupInfoViewController

/// Hosts `BackupInfoView`: why the recovery phrase matters, then Show
/// Recovery Phrase (after the PIN, unless setup just asked for it) or Skip.
@objc(DWBackupInfoViewController)
final class BackupInfoViewController: BaseViewController {
    @objc
    public weak var delegate: BackupInfoViewControllerDelegate?

    public var type: SecureWalletInfoType = .setup

    @objc
    var isSkipButtonHidden = true {
        didSet { viewModel.isSkipButtonHidden = isSkipButtonHidden }
    }

    @objc
    var isCloseButtonHidden = false {
        didSet { reloadCloseButton() }
    }

    /// Only explains, with no buttons: opened from "Why I should not take a
    /// screenshot?".
    @objc
    var isAllActionHidden = false {
        didSet {
            viewModel.areActionsHidden = isAllActionHidden
            reloadCloseButton()
        }
    }

    private let viewModel = BackupInfoViewModel()
    private var seedPhraseModel: DWPreviewSeedPhraseModel!

    /// `true` when this screen is the onboarding create-wallet step and no
    /// wallet exists yet — i.e. it will generate the phrase and create the
    /// wallet (lazily, in `createNewWalletIfNeeded`). `.setup` is also used
    /// for the "back up existing wallet" entry points, where it's `false`.
    private var createsNewWallet = false
    /// Picker state (selection + locked-after-creation); `selection` is read
    /// when the wallet is created.
    private let phraseLengthModel = RecoveryPhraseLengthPickerModel()

    @objc
    static func controller(with type: SecureWalletInfoType) -> BackupInfoViewController {
        let controller = BackupInfoViewController()
        controller.type = type
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if type == .setup {
            // Create-wallet entry point. The wallet itself is created lazily —
            // on "Show Recovery Phrase" or "Skip" — so the user can still pick
            // the phrase length on this screen first.
            seedPhraseModel = DWPreviewSeedPhraseModel()
            createsNewWallet = !WalletEnvironment.hasWallet
        }

        viewModel.isSkipButtonHidden = isSkipButtonHidden
        viewModel.areActionsHidden = isAllActionHidden
        viewModel.phraseLength = createsNewWallet ? phraseLengthModel : nil
        viewModel.onShowPhrase = { [weak self] in self?.backupButtonAction() }
        viewModel.onSkip = { [weak self] in self?.skipButtonAction() }

        view.backgroundColor = UIColor(named: "SecondaryBackgroundColor")
        embedSwiftUI(BackupInfoView(viewModel: viewModel))
        reloadCloseButton()
    }

    // MARK: Actions

    @objc
    private func closeAction() {
        delegate?.secureWalletRoutineDidCancel(self)
    }

    private func skipButtonAction() {
        // Skipping the backup must still leave the user with a wallet.
        createNewWalletIfNeeded()
        delegate?.secureWalletRoutineDidCancel(self)
    }

    private func backupButtonAction() {
        let authManager = AuthenticationService.shared

        if type == .setup && authManager.didAuthenticate {
            createNewWalletIfNeeded()
            showSeedPhraseViewController()
        } else {
            authManager.authenticate(withPrompt: nil,
                                     usingBiometricAuthentication: false,
                                     alertIfLockout: true) { [weak self] authenticated, _, _ in
                guard authenticated, let self else { return }

                if self.type != .setup {
                    self.seedPhraseModel = DWPreviewSeedPhraseModel()
                    self.seedPhraseModel.getOrCreateNewWallet()
                }

                self.createNewWalletIfNeeded()
                self.showSeedPhraseViewController()
            }
        }
    }

    /// Generates the recovery phrase at the chosen length and kicks off wallet
    /// creation — once. `DWPreviewSeedPhraseModel` caches the phrase it
    /// generated, so the next screen shows exactly the words being persisted
    /// even if this runs again.
    private func createNewWalletIfNeeded() {
        guard createsNewWallet else { return }
        seedPhraseModel.newWalletWordCount = UInt(phraseLengthModel.selection.rawValue)
        seedPhraseModel.getOrCreateNewWallet()
        phraseLengthModel.isLocked = true
    }

    private func showSeedPhraseViewController() {
        let controller = RecoveryPhraseViewController(model: seedPhraseModel, mode: .backup)
        controller.delegate = delegate
        navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: Close button

    private func reloadCloseButton() {
        guard isViewLoaded else { return }
        if isCloseButtonHidden || isAllActionHidden {
            navigationItem.rightBarButtonItem = nil
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close,
                                                                target: self,
                                                                action: #selector(closeAction))
        }
    }
}

// MARK: NavigationBarDisplayable

extension BackupInfoViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { isAllActionHidden == false }
}
