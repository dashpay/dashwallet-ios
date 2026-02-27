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
import SafariServices
import SwiftUI

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
        case .payWithNFC:
            performNFCReadingAction()
        case .localCurrency:
            showLocalCurrencyAction()
        case .importPrivateKey:
            showImportPrivateKey()
        case .switchToTestnet:
            Task {
                await DWEnvironment.sharedInstance().switchToTestnet()
            }
        case .switchToMainnet:
            Task {
                await DWEnvironment.sharedInstance().switchToMainnet()
            }
        case .reportAnIssue:
            break
        case .createUsername:
            showCreateUsername(withInvitation: nil, definedUsername: nil)
        case .receive:
            delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
        case .explore:
            showExploreDash()
        case .spend:
            showWhereToSpend()
        case .send:
            delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
        case .atm:
            showAtmList()
        case .sendToContact:
            showSendToContact()
        case .crowdNode:
            showCrowdNode()
        case .coinbase:
            showCoinbase()
        case .uphold:
            showUphold()
        case .topper:
            showTopper()
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
        navigationController.modalPresentationStyle = .fullScreen
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

    private func showWhereToSpend() {
        let controller = MerchantListViewController()
        controller.initialSegment = .all
        controller.payWithDashHandler = { [weak self] in
            guard let self = self else { return }
            self.delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
        }
        controller.onGiftCardPurchased = { [weak self] txId in
            guard let self = self else { return }
            self.dismiss(animated: true)
            self.showGiftCardDetails(txId: txId)
        }
        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true, completion: nil)
    }

    private func showAtmList() {
        let controller = AtmListViewController()
        controller.payWithDashHandler = { [weak self] in
            guard let self = self else { return }
            self.delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
        }
        controller.sellDashHandler = { [weak self] in
            guard let self = self else { return }
            self.delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
        }
        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true, completion: nil)
    }

    private func showSendToContact() {
        #if DASHPAY
        let controller = DWContactsViewController()
        controller.payDelegate = self
        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true, completion: nil)
        #endif
    }

    private func showCrowdNode() {
        if SyncingActivityMonitor.shared.state == .syncDone {
            let controller = CrowdNodeModelObjcWrapper.getRootVC()
            let navigationController = BaseNavigationController(rootViewController: controller)
            present(navigationController, animated: true, completion: nil)
        } else {
            let title = NSLocalizedString("The chain is syncing…", comment: "")
            let message = NSLocalizedString("Wait until the chain is fully synced before using CrowdNode.", comment: "")
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
            present(alert, animated: true)
        }
    }

    private func showCoinbase() {
        DSAuthenticationManager.sharedInstance().authenticate(withPrompt: nil, usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled, alertIfLockout: true) { [weak self] authenticated, _, _ in
            guard authenticated else { return }
            self?.showCoinbaseAuthenticated()
        }
    }

    private func showCoinbaseAuthenticated() {
        let geoblockedCountries = ["GB"]
        if let placemark = DWLocationManager.shared.currentPlacemark,
           geoblockedCountries.contains(placemark.isoCountryCode ?? "") {
            showModalDialog(
                style: .warning,
                icon: .system("exclamationmark.triangle.fill"),
                heading: NSLocalizedString("Due to regulatory constraints, you cannot use the Coinbase features while you are in the UK", comment: "Geoblock"),
                positiveButtonText: NSLocalizedString("OK", comment: "")
            )
            return
        }

        if Coinbase.shared.isAuthorized {
            let controller = IntegrationViewController.controller(model: CoinbaseEntryPointModel())
            controller.hidesBottomBarWhenPushed = true
            let navigationController = BaseNavigationController(rootViewController: controller)
            present(navigationController, animated: true, completion: nil)
        } else {
            let controller = ServiceOverviewViewController.controller()
            controller.hidesBottomBarWhenPushed = true
            let navigationController = BaseNavigationController(rootViewController: controller)
            present(navigationController, animated: true, completion: nil)
        }
    }

    private func showUphold() {
        let controller = IntegrationViewController.controller(model: UpholdPortalModel())
        controller.hidesBottomBarWhenPushed = true
        let navigationController = BaseNavigationController(rootViewController: controller)
        present(navigationController, animated: true, completion: nil)
    }

    private func showTopper() {
        guard let bundleName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String else { return }
        let urlString = TopperViewModel.shared.topperBuyUrl(walletName: bundleName)
        guard let url = URL(string: urlString) else { return }
        let safariViewController = SFSafariViewController.dw_controller(with: url)
        present(safariViewController, animated: true)
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

    // MARK: - Shortcut Customization

    func presentShortcutSelection(for position: Int) {
        let selectionView = ShortcutSelectionView { [weak self] selectedType in
            self?.applyShortcutCustomization(type: selectedType, at: position)
        }
        let hostingController = UIHostingController(rootView: selectionView)
        if let sheet = hostingController.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(hostingController, animated: true)
    }

    private func applyShortcutCustomization(type: ShortcutActionType, at position: Int) {
        var shortcuts: [Int] = HomeViewModel.shared.shortcutItems.map { $0.type.rawValue }

        guard position < shortcuts.count else { return }

        shortcuts[position] = type.rawValue
        DWGlobalOptions.sharedInstance().shortcuts = shortcuts.map { NSNumber(value: $0) }
        HomeViewModel.shared.reloadShortcuts()
        HomeViewModel.shared.recheckBannerAfterCustomization()
    }

    func showBackupWarningThenSelect(position: Int) {
        let alert = UIAlertController(
            title: NSLocalizedString("Back Up Your Wallet", comment: ""),
            message: NSLocalizedString("You haven't backed up your recovery phrase yet. Would you like to back up now before removing this shortcut?", comment: ""),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("Back Up Now", comment: ""), style: .default) { [weak self] _ in
            self?.secureWalletAction()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Skip", comment: ""), style: .destructive) { [weak self] _ in
            self?.presentShortcutSelection(for: position)
        })
        present(alert, animated: true)
    }

    // MARK: - DWLocalCurrencyViewControllerDelegate

    func localCurrencyViewController(_ controller: DWLocalCurrencyViewController, didSelectCurrency currencyCode: String) {
        controller.navigationController?.dismiss(animated: true, completion: nil)
    }

    func localCurrencyViewControllerDidCancel(_ controller: DWLocalCurrencyViewController) {
        controller.navigationController?.dismiss(animated: true, completion: nil)
    }

    // MARK: - DWExploreTestnetViewControllerDelegate

    func exploreViewControllerShowSendPayment(_ controller: ExploreViewController) {
        delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
    }

    func exploreViewControllerShowReceivePayment(_ controller: ExploreViewController) {
        delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
    }
    
    func exploreViewControllerShowGiftCard(_ controller: ExploreViewController, txId: Data) {
        showGiftCardDetails(txId: txId)
    }
}
