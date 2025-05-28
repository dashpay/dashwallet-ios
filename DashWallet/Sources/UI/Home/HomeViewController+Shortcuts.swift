//  
//  Created by Andrei Ashikhmin
//  Copyright © 2024 Dash Core Group. All rights reserved.
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

extension HomeViewController: DWLocalCurrencyViewControllerDelegate, ExploreViewControllerDelegate {

    func performAction(for action: ShortcutAction, sender: UIView?) {
        switch action.type {
        case .secureWallet:
            secureWalletAction()
        case .scanToPay:
            performScanQRCodeAction()
        case .payToAddress:
            delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.enterAddress.rawValue)
        case .buySellDash:
            buySellDashAction()
        case .syncNow:
            DWSettingsMenuModel.rescanBlockchainAction(from: self, sourceView: sender!, sourceRect: sender!.bounds, completion: nil)
        case .payWithNFC:
            performNFCReadingAction()
        case .localCurrency:
            showLocalCurrencyAction()
        case .importPrivateKey:
            showImportPrivateKey()
        case .switchToTestnet:
            DWSettingsMenuModel.switchToTestnet { success in
                // NOP
            }
        case .switchToMainnet:
            DWSettingsMenuModel.switchToMainnet { success in
                // NOP
            }
        case .reportAnIssue:
            break
        case .createUsername:
            showCreateUsername(withInvitation: nil, definedUsername: nil)
        case .receive:
            delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
        case .explore:
            showExploreDash()
        }
    }

    // MARK: - Private

    private func secureWalletAction() {
        DSAuthenticationManager.sharedInstance().authenticate(withPrompt: nil, usingBiometricAuthentication: false, alertIfLockout: true) { [weak self] authenticated, usedBiometrics, cancelled in
            guard authenticated else { return }
            self?.secureWalletActionAuthenticated()
        }
    }

    private func secureWalletActionAuthenticated() {
        let controller = BackupInfoViewController.controller(with: .setup)
        controller.delegate = self

        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true, completion: nil)
    }

    private func buySellDashAction() {
        DSAuthenticationManager.sharedInstance().authenticate(withPrompt: nil, usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled, alertIfLockout: true) { [weak self] authenticated, usedBiometrics, cancelled in
            guard authenticated else { return }
            self?.buySellDashActionAuthenticated()
        }
    }

    private func buySellDashActionAuthenticated() {
        let controller = BuySellPortalViewController.controller()
        controller.showCloseButton = true

        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true, completion: nil)
    }

    private func showLocalCurrencyAction() {
        let controller = DWLocalCurrencyViewController(navigationAppearance: .white, presentationMode: .dialog, currencyCode: nil)
        controller.delegate = self
        presentControllerModallyInNavigationController(controller)
    }

    private func showImportPrivateKey() {
        let controller = DWImportWalletInfoViewController.createController()
        controller.delegate = self
        presentControllerModallyInNavigationController(controller)
    }

    func showCreateUsername(withInvitation invitationURL: URL?, definedUsername: String?) {
        #if DASHPAY
        let controller = CreateUsernameViewController(dashPayModel: model.dashPayModel, invitationURL: nil, definedUsername: nil)
        controller.hidesBottomBarWhenPushed = true
        controller.completionHandler = { result in
            if (result) {
                self.view.dw_showInfoHUD(withText: NSLocalizedString("Username was successfully requested", comment: "Usernames"), offsetForNavBar:true)
            } else {
                self.view.dw_showInfoHUD(withText: NSLocalizedString("Your request was cancelled", comment: "Usernames"), offsetForNavBar:true)
            }
        }
        self.navigationController?.pushViewController(controller, animated: true)
        #endif
    }

    private func showExploreDash() {
        let controller = ExploreViewController()
        controller.delegate = self
        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true, completion: nil)
    }

    private func presentControllerModallyInNavigationController(_ controller: UIViewController) {
        if #available(iOS 13.0, *) {
            presentControllerModallyInNavigationController(controller, modalPresentationStyle: .automatic)
        } else {
            presentControllerModallyInNavigationController(controller, modalPresentationStyle: .fullScreen)
        }
    }

    private func presentControllerModallyInNavigationController(_ controller: UIViewController, modalPresentationStyle: UIModalPresentationStyle) {
        let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismissModalControllerBarButtonAction(_:)))
        controller.navigationItem.leftBarButtonItem = cancelButton

        let navigationController = BaseNavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = modalPresentationStyle
        present(navigationController, animated: true, completion: nil)
    }

    @objc private func dismissModalControllerBarButtonAction(_ sender: Any) {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - DWLocalCurrencyViewControllerDelegate

    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        controller.navigationController?.dismiss(animated: true, completion: nil)
    }

    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        controller.navigationController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - DWExploreTestnetViewControllerDelegate

    func exploreTestnetViewControllerShowSendPayment(_ controller: ExploreViewController) {
        delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
    }

    func exploreTestnetViewControllerShowReceivePayment(_ controller: ExploreViewController) {
        delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
    }
}
