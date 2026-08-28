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

import Foundation
import SwiftUI
import UIKit

// MARK: - BackupInfoItem

private enum BackupInfoItem {
    case notStoredByDash
    case unableToRestore
}

extension BackupInfoItem {
    var title: String {
        switch self {
        case .notStoredByDash:
            return NSLocalizedString("Dash Core Group does NOT store this recovery phrase",
                                     comment: "Recovery phrase backup: security warning title — Dash Core Group does not store the phrase")
        case .unableToRestore:
            return NSLocalizedString("You will NOT be able to restore the wallet without a recovery phrase",
                                     comment: "Recovery phrase backup: security warning title — the phrase is required to restore the wallet")
        }
    }

    var description: String {
        switch self {
        case .notStoredByDash:
            return NSLocalizedString("Anyone that has your recovery phrase can access your funds.",
                                     comment: "Recovery phrase backup: security warning body — anyone with the phrase can spend the funds")
        case .unableToRestore:
            return NSLocalizedString("Write it in a safe place and don’t show it to anyone.",
                                     comment: "Recovery phrase backup: security warning body — keep the phrase written down and private")
        }
    }

    var icon: UIImage {
        switch self {
        case .notStoredByDash: return UIImage(named: "backup-not-stored-icon")!
        case .unableToRestore: return UIImage(named: "backup-recovery-icon")!
        }
    }
}

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

@objc(DWBackupInfoViewController)
final class BackupInfoViewController: BaseViewController {
    @IBOutlet private var titleLabel: UILabel!
    @IBOutlet private var subtitleLabel: UILabel!

    @IBOutlet private var contentView: UIStackView!

    @IBOutlet private var bottomButtonStack: UIStackView!
    @IBOutlet private var showRecoveryPhraseButton: UIButton!
    @IBOutlet private var skipButton: UIButton!

    private var closeButton: UIBarButtonItem!
    private var seedPhraseModel: DWPreviewSeedPhraseModel!

    /// `true` when this screen is the onboarding create-wallet step and no
    /// wallet exists yet — i.e. it will generate the phrase and create the
    /// wallet (lazily, in `createNewWalletIfNeeded`). `.setup` is also used
    /// for the "back up existing wallet" entry points, where it's `false`.
    private var createsNewWallet = false
    /// Picker state (selection + locked-after-creation), observed by the hosted
    /// SwiftUI picker; `selection` is read when the wallet is created.
    private let phraseLengthModel = RecoveryPhraseLengthPickerModel()
    private var phraseLengthPickerHost: UIHostingController<RecoveryPhraseLengthPickerHost>?

    @objc
    public weak var delegate: BackupInfoViewControllerDelegate?

    public var type: SecureWalletInfoType = .setup

    @objc
    var isSkipButtonHidden = true {
        didSet {
            if isViewLoaded {
                skipButton?.isHidden = isSkipButtonHidden
            }
        }
    }

    @objc
    var isCloseButtonHidden = false {
        didSet {
            if isViewLoaded {
                reloadCloseButton()
            }
        }
    }

    @objc
    var isAllActionHidden = false {
        didSet {
            if isViewLoaded {
                reloadView()
            }
        }
    }

    @objc
    private func closeAction() {
        delegate?.secureWalletRoutineDidCancel(self)
    }

    @IBAction
    func skipButtonAction() {
        // Skipping the backup must still leave the user with a wallet.
        createNewWalletIfNeeded()
        delegate?.secureWalletRoutineDidCancel(self)
    }

    @IBAction
    func backupButtonAction() {
        let authManager = AuthenticationService.shared
        
        if type == .setup && authManager.didAuthenticate {
            createNewWalletIfNeeded()
            showSeedPhraseViewController()
        } else {
            authManager.authenticate(withPrompt: nil,
                   usingBiometricAuthentication: false,
                   alertIfLockout: true) { [weak self] authenticated, _, _ in
                guard authenticated else {
                    return
                }

                guard let self else {
                    return
                }

                if type != .setup {
                    self.seedPhraseModel = DWPreviewSeedPhraseModel()
                    self.seedPhraseModel.getOrCreateNewWallet()
                }

                self.createNewWalletIfNeeded()
                self.showSeedPhraseViewController()
            }
        }
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


        configureHierarchy()
    }

    @objc
    static func controller(with type: SecureWalletInfoType) -> BackupInfoViewController {
        let controller = vc(BackupInfoViewController.self, from: sb("BackupInfo"))
        controller.type = type
        return controller
    }
}

extension BackupInfoViewController {
    private func configureHierarchy() {
        titleLabel.text = NSLocalizedString("Backup your recovery phrase", comment: "Back up wallet")
        subtitleLabel
            .text = NSLocalizedString("You will need this recovery phrase to access your funds if this device is lost, damaged or if Dash Wallet is uninstalled from this device.",
                                      comment: "Back up wallet")
        showRecoveryPhraseButton.setTitle(NSLocalizedString("Show Recovery Phrase", comment: "Back up wallet"), for: .normal)
        skipButton.setTitle(NSLocalizedString("Skip", comment: "Back up wallet"), for: .normal)

        show(item: .notStoredByDash)
        show(item: .unableToRestore)
        installPhraseLengthPickerIfNeeded()

        skipButton.isHidden = isSkipButtonHidden
        reloadCloseButton()
        reloadView()
    }

    private func reloadView() {
        if isAllActionHidden {
            hideCloseButton()
            bottomButtonStack.isHidden = true
        } else {
            showCloseButtonIfNeeded()
            bottomButtonStack.isHidden = false
        }
    }

    /// Onboarding only (`createsNewWallet`): lets the user pick 12 or 24 words
    /// before the phrase is generated. Hosted SwiftUI at the top of the button
    /// stack, driven by `phraseLengthModel`; the host view is collapsed once
    /// the model is locked (wallet created).
    private func installPhraseLengthPickerIfNeeded() {
        guard createsNewWallet, phraseLengthPickerHost == nil else { return }

        let host = UIHostingController(rootView: RecoveryPhraseLengthPickerHost(model: phraseLengthModel))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        addChild(host)
        bottomButtonStack.insertArrangedSubview(host.view, at: 0)
        bottomButtonStack.setCustomSpacing(20, after: host.view)
        host.didMove(toParent: self)
        phraseLengthPickerHost = host
    }

    /// Generates the recovery phrase at the chosen length and kicks off wallet
    /// creation — once. `DWPreviewSeedPhraseModel` caches the phrase it
    /// generated, so the preview screen shows exactly the words being
    /// persisted even if this runs again.
    private func createNewWalletIfNeeded() {
        guard createsNewWallet else { return }
        seedPhraseModel.newWalletWordCount = UInt(phraseLengthModel.selection.rawValue)
        seedPhraseModel.getOrCreateNewWallet()
        phraseLengthModel.isLocked = true
        phraseLengthPickerHost?.view.isHidden = true
    }

    private func showSeedPhraseViewController() {
        let controller = BackupSeedPhraseViewController(model: seedPhraseModel)
        controller.shouldCreateNewWalletOnScreenshot = shouldCreateNewWalletOnScreenshot
        controller.delegate = delegate
        navigationController?.pushViewController(controller, animated: true)
    }

    private func reloadCloseButton() {
        if isCloseButtonHidden {
            hideCloseButton()
        } else {
            showCloseButton()
        }
    }

    private func show(item: BackupInfoItem) {
        let view = itemView(from: item)
        contentView.addArrangedSubview(view)
    }

    private func itemView(from item: BackupInfoItem) -> BackupInfoItemView {
        let view = BackupInfoItemView.view()
        view.titleLabel.text = item.title
        view.descriptionLabel.text = item.description
        view.iconView.image = item.icon
        return view
    }

    private func showCloseButtonIfNeeded() {
        if !isCloseButtonHidden {
            showCloseButton()
        }
    }

    private func showCloseButton() {
        let item = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeAction))
        navigationItem.rightBarButtonItem = item

        closeButton = item
    }

    private func hideCloseButton() {
        navigationItem.rightBarButtonItem = nil
        closeButton = nil
    }
}

extension BackupInfoViewController {
    var shouldCreateNewWalletOnScreenshot: Bool {
        false
    }
}

// MARK: NavigationBarDisplayable

extension BackupInfoViewController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { isAllActionHidden == false }
}
