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

@objc(DWSetupViewControllerDelegate)
protocol SetupViewControllerDelegate: AnyObject {
    func setupViewControllerDidFinish(_ controller: SetupViewController)
}

/// Wallet setup for `DWAppRootViewController`: hosts `SetupView` and runs
/// what follows Create a New Wallet or Recover Wallet — Set PIN, then Face ID
/// or Touch ID, then backing up the recovery phrase — each step replacing the
/// one before it.
@objc(DWSetupViewController)
final class SetupViewController: UIViewController, NavigationFullscreenable {
    @objc weak var delegate: SetupViewControllerDelegate?

    /// Recovering waits for the PIN: the wallet is created from the phrase
    /// only once a PIN protects it.
    private var recoverWalletCommand: DWRecoverWalletCommand?
    private var launchingWasDeferred = false

    @objc
    static func controller() -> SetupViewController {
        SetupViewController()
    }

    /// Setup follows onboarding rather than the launch screen: the logo is
    /// already where it settles.
    @objc
    func setLaunchingAsDeferredController() {
        launchingWasDeferred = true
    }

    var requiresNoNavigationBar: Bool { true }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        embedSwiftUI(SetupView(
            skipsLogoAnimation: launchingWasDeferred,
            onCreate: { [weak self] in self?.createWallet() },
            onRecover: { [weak self] in self?.recoverWallet() }
        ))
    }

    // MARK: Actions

    private func createWallet() {
        recoverWalletCommand = nil
        DWGlobalOptions.sharedInstance().walletNeedsBackup = true

        guard let next = nextController() else {
            assertionFailure("A new wallet always has a setup step left")
            return
        }
        navigationController?.setViewControllers([self, next], animated: true)
    }

    private func recoverWallet() {
        recoverWalletCommand = nil

        let controller = DWRecoverViewController()
        controller.action = .recover
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: Steps

    private func nextController() -> UIViewController? {
        if SetPinViewModel.shouldSetPin {
            let controller = SetPinViewController(intent: .createNewWallet)
            controller.delegate = self
            return controller
        }
        if BiometricAuthViewModel.shouldOffer {
            let controller = BiometricAuthViewController()
            controller.onFinish = { [weak self] in self?.continueOrCompleteSetup() }
            return controller
        }
        if DWPreviewSeedPhraseModel.shouldVerifyPassphrase {
            let controller = BackupInfoViewController.controller(with: .setup)
            controller.delegate = self
            controller.isCloseButtonHidden = true
            controller.isSkipButtonHidden = false
            return controller
        }
        return nil
    }

    private func continueOrCompleteSetup() {
        if let next = nextController() {
            navigationController?.setViewControllers([self, next], animated: true)
        } else {
            completeSetup()
        }
    }

    private func completeSetup() {
        delegate?.setupViewControllerDidFinish(self)
    }
}

// MARK: - SetPinViewControllerDelegate

extension SetupViewController: SetPinViewControllerDelegate {
    func setPinViewControllerDidCancel(_ controller: SetPinViewController) {
        recoverWalletCommand = nil
        navigationController?.popViewController(animated: true)
    }

    func setPinViewControllerDidSetPin(_ controller: SetPinViewController) {
        // Recovering: the wallet is created now that a PIN protects it.
        recoverWalletCommand?.execute()
        recoverWalletCommand = nil

        continueOrCompleteSetup()
    }
}

// MARK: - BackupInfoViewControllerDelegate

extension SetupViewController: BackupInfoViewControllerDelegate {
    func secureWalletRoutineDidCancel(_ controller: UIViewController) {
        completeSetup()
    }

    func secureWalletRoutineDidVerify(_ controller: UIViewController) { }

    func secureWalletRoutineDidFinish(_ controller: VerifiedSuccessfullyViewController) {
        completeSetup()
    }
}

// MARK: - DWRecoverViewControllerDelegate

extension SetupViewController: DWRecoverViewControllerDelegate {
    func recoverViewControllerDidRecoverWallet(_ controller: DWRecoverViewController,
                                               recover recoverCommand: DWRecoverWalletCommand) {
        // Recovering waits for a PIN; the phrase was just entered, so there is
        // nothing to back up.
        recoverWalletCommand = recoverCommand
        DWGlobalOptions.sharedInstance().walletNeedsBackup = false

        continueOrCompleteSetup()
    }

    func recoverViewControllerDidWipe(_ controller: DWRecoverViewController) {
        navigationController?.popViewController(animated: true)
    }
}
