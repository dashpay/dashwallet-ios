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

import SwiftUI
import UIKit

/// When the lock screen asks for biometrics by itself.
@objc(DWLockScreenViewControllerUnlockMode)
enum LockScreenUnlockMode: Int {
    /// Right away: the app was just launched.
    case instantly
    /// When the app becomes active: it was locked on going to the background.
    case applicationDidBecomeActive
}

@objc(DWLockScreenViewControllerDelegate)
protocol LockScreenViewControllerDelegate: AnyObject {
    func lockScreenViewControllerDidUnlock(_ controller: LockScreenViewController)
    /// The support-assisted global wipe has already completed successfully.
    func lockScreenViewControllerDidWipe(_ controller: LockScreenViewController)
}

/// Hosts `LockScreenView` for `DWAppRootViewController`, and runs what the
/// screen starts: Forgot PIN, Quick Receive and Scan to Send.
///
/// A `DWBasePayViewController`, as the Objective-C screen it replaces was:
/// Scan to Send pays from here, before the wallet is unlocked.
@objc(DWLockScreenViewController)
final class LockScreenViewController: DWBasePayViewController, NavigationFullscreenable {
    @objc var unlockMode: LockScreenUnlockMode = .instantly
    @objc weak var delegate: LockScreenViewControllerDelegate?

    private lazy var viewModel = LockScreenViewModel()

    @objc(lockScreenWithUnlockMode:payModel:)
    static func lockScreen(unlockMode: LockScreenUnlockMode, payModel: DWPayModelProtocol) -> LockScreenViewController {
        let controller = LockScreenViewController()
        controller.unlockMode = unlockMode
        controller.payModel = payModel
        return controller
    }

    /// Sends from the lock screen keep the balance hidden.
    override var locksBalance: Bool {
        get { true }
        set { }
    }

    var requiresNoNavigationBar: Bool { true }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.onUnlock = { [weak self] in
            guard let self else { return }
            self.delegate?.lockScreenViewControllerDidUnlock(self)
        }

        let screen = LockScreenView(
            viewModel: viewModel,
            onForgotPin: { [weak self] in self?.forgotPin() },
            onQuickReceive: { [weak self] in self?.quickReceive() },
            onScanToSend: { [weak self] in self?.performScanQRCodeAction() }
        )
        let hosting = UIHostingController(rootView: screen)
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)

        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.startCheckingAuthState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if unlockMode == .instantly {
            viewModel.tryOnceToUnlockUsingBiometrics(isCovered: presentedViewController != nil)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.stopCheckingAuthState()
    }

    @objc private func applicationDidBecomeActive() {
        viewModel.tryOnceToUnlockUsingBiometrics(isCovered: presentedViewController != nil)
        viewModel.startCheckingAuthState()
    }

    @objc private func applicationDidEnterBackground() {
        viewModel.resetBiometricsAttempt()
        viewModel.stopCheckingAuthState()
    }

    // MARK: Quick Receive

    private func quickReceive() {
        // The receive screen narrowed to Receive for the locked context.
        present(PaymentsLandingHostingController.quickReceiveController(), animated: true)
    }

    // MARK: Forgot PIN

    private func forgotPin() {
        viewModel.stopCheckingAuthState()

        // No PIN record: nothing was forgotten and no counter can advance, so
        // go straight to the recovery phrase. It stays mandatory — the PIN
        // guards spending, so a missing record must not hand the wallet over.
        guard viewModel.hasPinSet else {
            presentRecovery(action: .resetPin)
            return
        }

        // Prove ownership with the recovery phrase, then set a new PIN and
        // keep the wallet. Only past the wipe threshold is wiping offered too.
        guard viewModel.isAllowedToWipe else {
            presentRecovery(action: .resetPin)
            return
        }

        let sheet = UIAlertController(title: nil, message: nil,
                                      preferredStyle: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet)
        sheet.addAction(UIAlertAction(title: String(localized: "Reset PIN", comment: ""), style: .default) { [weak self] _ in
            self?.presentRecovery(action: .resetPin)
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Wipe All Wallets", comment: ""), style: .destructive) { [weak self] _ in
            self?.confirmWipe()
        })
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel", comment: ""), style: .cancel) { [weak self] _ in
            self?.viewModel.startCheckingAuthState()
        })
        present(sheet, animated: true)
    }

    private func confirmWipe() {
        WalletDeleteAllConfirmationCoordinator.present(
            from: self,
            cancelHandler: { [weak self] in self?.viewModel.startCheckingAuthState() },
            deleteAllHandler: { [weak self] in self?.presentRecovery(action: .supportWipe) }
        )
    }

    /// The recovery phrase screen, full screen with Cancel on the right: the
    /// shared navigation controller clears the left items of a root screen.
    private func presentRecovery(action: DWRecoverAction) {
        let controller = DWRecoverViewController()
        controller.action = action
        controller.delegate = self
        controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelRecovery))
        presentFullScreen(controller)
    }

    @objc private func cancelRecovery() {
        dismissAndResume()
    }

    private func presentSetNewPin() {
        // Forgot PIN changes an existing PIN; with no PIN record it sets the first.
        let controller = DWSetPinViewController(intent: viewModel.hasPinSet ? .changePin : .setPin)
        controller.delegate = self
        presentFullScreen(controller)
    }

    private func presentFullScreen(_ controller: UIViewController) {
        let navigation = BaseNavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func dismissAndResume() {
        dismiss(animated: true) { [weak self] in
            self?.viewModel.startCheckingAuthState()
        }
    }
}

// MARK: - DWRecoverViewControllerDelegate

extension LockScreenViewController: DWRecoverViewControllerDelegate {
    func recoverViewControllerDidVerifyPhrase(forPinReset controller: DWRecoverViewController) {
        // Ownership proven, wallet untouched: set a new PIN, which unlocks.
        dismiss(animated: true) { [weak self] in
            self?.presentSetNewPin()
        }
    }

    func recoverViewControllerDidWipe(_ controller: DWRecoverViewController) {
        guard controller.action == .supportWipe else {
            assertionFailure("ResetPin recovery never wipes")
            dismissAndResume()
            return
        }
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.lockScreenViewControllerDidWipe(self)
        }
    }

    func recoverViewControllerDidRecoverWallet(_ controller: DWRecoverViewController,
                                               recover recoverCommand: DWRecoverWalletCommand) {
        assertionFailure("ResetPin recovery never recovers a wallet")
        dismissAndResume()
    }
}

// MARK: - DWSetPinViewControllerDelegate

extension LockScreenViewController: DWSetPinViewControllerDelegate {
    func setPinViewControllerDidSetPin(_ controller: DWSetPinViewController) {
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.delegate?.lockScreenViewControllerDidUnlock(self)
        }
    }

    func setPinViewControllerDidCancel(_ controller: DWSetPinViewController) {
        // The phrase was proven but no new PIN set: back to the lock screen,
        // where the old PIN still works, or Set PIN is offered again.
        dismissAndResume()
    }
}
