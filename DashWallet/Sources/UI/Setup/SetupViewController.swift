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

/// Wallet setup for `DWAppRootViewController`: hosts `SetupView` and shows
/// the steps `SetupFlowModel` picks after Create a New Wallet or Recover
/// Wallet, each replacing the one before it.
@objc(DWSetupViewController)
final class SetupViewController: UIViewController, NavigationFullscreenable {
    @objc weak var delegate: SetupViewControllerDelegate?

    private let flow = SetupFlowModel()
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
        guard let step = flow.createWallet() else {
            assertionFailure("A new wallet always has a setup step left")
            return
        }
        navigationController?.setViewControllers([self, controller(for: step)], animated: true)
    }

    private func recoverWallet() {
        flow.startRecovering()

        let controller = RecoverWalletViewController()
        controller.action = .recover
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }

    // MARK: Steps

    private func controller(for step: SetupFlowModel.Step) -> UIViewController {
        switch step {
        case .setPin:
            let controller = SetPinViewController(intent: .createNewWallet)
            controller.delegate = self
            return controller
        case .biometrics:
            let controller = BiometricAuthViewController()
            controller.onFinish = { [weak self] in
                guard let self else { return }
                self.show(self.flow.nextStep())
            }
            return controller
        case .backup:
            let controller = BackupInfoViewController.controller(with: .setup)
            controller.delegate = self
            controller.isCloseButtonHidden = true
            controller.isSkipButtonHidden = false
            return controller
        }
    }

    /// Shows `step`, or completes setup when there is none left.
    private func show(_ step: SetupFlowModel.Step?) {
        if let step {
            navigationController?.setViewControllers([self, controller(for: step)], animated: true)
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
        flow.didCancelPin()
        navigationController?.popViewController(animated: true)
    }

    func setPinViewControllerDidSetPin(_ controller: SetPinViewController) {
        show(flow.didSetPin())
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

// MARK: - RecoverWalletViewControllerDelegate

extension SetupViewController: RecoverWalletViewControllerDelegate {
    func recoverViewControllerDidRecoverWallet(_ controller: RecoverWalletViewController,
                                               recover recoverCommand: DWRecoverWalletCommand) {
        show(flow.didEnterRecoveryPhrase { recoverCommand.execute() })
    }

    func recoverViewControllerDidWipe(_ controller: RecoverWalletViewController) {
        navigationController?.popViewController(animated: true)
    }
}
