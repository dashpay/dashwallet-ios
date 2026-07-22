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
import DashUIKit
import SwiftDashSDK

extension HomeViewController: DWLocalCurrencyViewControllerDelegate {
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
            break
        case .switchToTestnet:
            Task {
                await WalletEnvironment.switchToNetwork(.testnet)
            }
        case .switchToMainnet:
            Task {
                await WalletEnvironment.switchToNetwork(.mainnet)
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
        case .getTestDash:
            showTestnetFaucet()
        case .switchWallet:
            showSwitchWallet()
        case .dashDEX:
            dashDEXAction()
        }
    }

    // MARK: - Switch Wallet

    /// Entry point of the Switch Wallet shortcut. Presentation scales with how
    /// many OTHER wallets exist: one → confirmation alert directly; two to
    /// five → bottom-sheet picker (then the same confirmation); more → the
    /// full Wallets screen (which has its own switch confirmation). The
    /// shortcut is hidden/degraded while only one wallet exists, so an empty
    /// list here is just a defensive no-op.
    private func showSwitchWallet() {
        let walletsViewModel = WalletsViewModel()
        walletsViewModel.reload()
        let others = walletsViewModel.rows.filter { !$0.isActive }
        guard !others.isEmpty else { return }

        if others.count == 1 {
            confirmWalletSwitch(to: others[0], viewModel: walletsViewModel)
        } else if others.count <= 5 {
            let dialog = WalletSwitchDialog(rows: others) { [weak self] row in
                self?.dismiss(animated: true) {
                    self?.confirmWalletSwitch(to: row, viewModel: walletsViewModel)
                }
            }
            let hostingController = UIHostingController(rootView: dialog)
            hostingController.setDetent(WalletSwitchDialog.height(rowCount: others.count))
            present(hostingController, animated: true)
        } else {
            guard let navigationController else { return }
            let controller = UIHostingController(rootView: WalletsScreen(vc: navigationController))
            controller.hidesBottomBarWhenPushed = true
            navigationController.pushViewController(controller, animated: true)
        }
    }

    /// The always-shown switch confirmation. The switch itself runs through
    /// `WalletsViewModel.switchWallet` (shared runtime call + error logging);
    /// the home screen refreshes via the active-wallet-change notification.
    /// `viewModel` is captured by the action so it outlives the alert.
    private func confirmWalletSwitch(to row: WalletRow, viewModel: WalletsViewModel) {
        let alert = UIAlertController(
            title: NSLocalizedString("Switch Wallet", comment: "Wallets"),
            message: String(
                format: NSLocalizedString("Would you like to switch to \"%@\"? You can always switch back later.", comment: "Wallets"),
                row.displayName),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("Switch", comment: "Wallets"), style: .default) { _ in
            viewModel.switchWallet(to: row.walletId)
        })
        present(alert, animated: true)
    }

    // MARK: - Private

    private func secureWalletAction() {
        AuthenticationService.shared.authenticate(withPrompt: nil, usingBiometricAuthentication: false, alertIfLockout: true) { [weak self] authenticated, usedBiometrics, cancelled in
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
        AuthenticationService.shared.authenticate(withPrompt: nil, usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled, alertIfLockout: true) { [weak self] authenticated, usedBiometrics, cancelled in
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

    func showCreateUsername(withInvitation invitationURL: URL?, definedUsername: String?) {
        #if DASHPAY
        // Invitation claim: the voucher funds the registration, so the
        // shielded get-ready interstitial doesn't apply — straight to
        // the form in invitation mode.
        if invitationURL != nil {
            pushCreateUsernameForm(invitationURL: invitationURL, definedUsername: definedUsername)
            return
        }
        // Route through the shielded get-ready interstitial whenever
        // the privacy-preserving funding path isn't ready (needs funds
        // / maturing / pool below minimum) so the privacy clock starts
        // at first intent. `nil` (host not hydrated yet) falls through
        // to the form — its own cost rules gate submission.
        let readiness = ShieldedIdentityFundingReadiness.shared.evaluate(
            requiredCredits: ShieldedIdentityFundingReadiness.standardDenominationCredits)
        if let readiness, readiness.state != .ready {
            showJoinDashPayReadiness()
        } else {
            pushCreateUsernameForm()
        }
        #endif
    }

    #if DASHPAY
    /// Manual redeem entry (Join DashPay dialog → "Have an invitation?"):
    /// paste/scan screen, then the username form in invitation mode.
    func showClaimInvitation() {
        ClaimInvitationFlow.pushRedeemScreen(
            on: navigationController,
            dashPayModel: model.dashPayModel)
    }
    #endif

    #if DASHPAY
    private func showJoinDashPayReadiness() {
        let screen = JoinDashPayReadinessScreen(
            onAddFunds: { [weak self] suggestedDash in
                let controller = InternalTransferHostingController(prefillDashAmount: suggestedDash)
                controller.hidesBottomBarWhenPushed = true
                self?.navigationController?.pushViewController(controller, animated: true)
            },
            onProceed: { [weak self] in
                self?.pushCreateUsernameForm()
            })
        let hosting = UIHostingController(rootView: screen)
        hosting.view.backgroundColor = UIColor.dw_background()
        hosting.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(hosting, animated: true)
    }

    private func pushCreateUsernameForm(invitationURL: URL? = nil, definedUsername: String? = nil) {
        let controller = CreateUsernameViewController(dashPayModel: model.dashPayModel, invitationURL: invitationURL, definedUsername: definedUsername)
        controller.hidesBottomBarWhenPushed = true
        controller.completionHandler = { result in
            if (result) {
                self.view.dw_showInfoHUD(withText: NSLocalizedString("Username was successfully requested", comment: "Usernames"), offsetForNavBar:true)
            } else {
                self.view.dw_showInfoHUD(withText: NSLocalizedString("Your request was cancelled", comment: "Usernames"), offsetForNavBar:true)
            }
        }
        self.navigationController?.pushViewController(controller, animated: true)
    }
    #endif

    private func showExploreDash() {
        guard let navController = navigationController else { return }
        let screen = ExploreMenuScreen(
            vc: navController,
            onShowSendPayment: { [weak self] in
                self?.delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
            },
            onShowReceivePayment: { [weak self] in
                self?.delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.receive.rawValue)
            },
            onShowGiftCard: { [weak self] txId in
                self?.showGiftCardDetails(txId: txId)
            }
        )
        let hostingController = UIHostingController(rootView: screen)
        hostingController.hidesBottomBarWhenPushed = true
        navController.pushViewController(hostingController, animated: true)
    }

    private func showWhereToSpend() {
        let controller = MerchantListViewController()
        controller.initialSegment = .all
        controller.customNavBar = MerchantListViewController.CustomNavBarConfiguration(
            title: NSLocalizedString("Where to Spend", comment: ""),
            onBack: { [weak controller] in controller?.dismiss(animated: true) },
            onInfo: nil
        )
        controller.payWithDashHandler = { [weak self] in
            guard let self = self else { return }
            self.delegate?.showPaymentsController(withActivePage: PaymentsViewControllerState.pay.rawValue)
        }
        controller.onGiftCardPurchased = { [weak self] txId in
            guard let self = self else { return }
            self.showGiftCardDetails(txId: txId)
        }
        let navigationController = BaseNavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
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
        // Row #18: open the SwiftUI contacts screen; paying happens
        // from a contact's profile sheet (WalletSendService.sendToContact).
        let controller = UIHostingController(rootView: ContactsScreen())
        present(controller, animated: true)
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
        AuthenticationService.shared.authenticate(withPrompt: nil, usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled, alertIfLockout: true) { [weak self] authenticated, _, _ in
            guard authenticated else { return }
            self?.showCoinbaseAuthenticated()
        }
    }

    private func showCoinbaseAuthenticated() {
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

    /// Testnet faucet, driven fully in-app (same flow as SwiftExampleApp's
    /// ReceiveAddressView): the SDK's `TestnetFaucet` client solves the
    /// faucet's soft cap.js proof-of-work on-device and posts the wallet's
    /// receive address to `/api/core-faucet` — 1 tDash arrives without
    /// leaving the app. On rate limit or any failure it falls back to the
    /// legacy behavior: copy the address, open the web faucet, and say why.
    private func showTestnetFaucet() {
        guard WalletEnvironment.isTestnet else { return }
        guard let address = SwiftDashSDKReceiveAddressReader.receiveAddress() else {
            openWebFaucetFallback(address: nil, reason: nil)
            return
        }

        view.dw_showProgressHUD(withMessage: NSLocalizedString("Requesting tDash…", comment: "Testnet faucet"))
        Task { @MainActor in
            let outcome = await TestnetFaucet().requestCoreDash(address: address)
            self.view.dw_hideProgressHUD()
            switch outcome {
            case .sent(_, let amount):
                let dash = amount == amount.rounded()
                    ? String(format: "%.0f", amount)
                    : String(format: "%.4f", amount)
                self.view.dw_showInfoHUD(
                    withText: String(
                        format: NSLocalizedString("%@ tDash requested — it will arrive shortly", comment: "Testnet faucet"),
                        dash),
                    offsetForNavBar: true)
            case .rateLimited(let message):
                self.openWebFaucetFallback(address: address, reason: message)
            case .failed(let reason):
                self.openWebFaucetFallback(address: address, reason: reason)
            }
        }
    }

    /// Web fallback for rate-limit/failure: copy the receive address (the
    /// faucet page doesn't prefill it) and open the faucet in-app. The
    /// reason is logged, not toasted — the Safari sheet covers the HUD.
    private func openWebFaucetFallback(address: String?, reason: String?) {
        if let reason {
            DWLogger.log("Faucet: falling back to web — \(reason)")
        }
        if let address {
            UIPasteboard.general.string = address
        }
        let safariViewController = SFSafariViewController.dw_controller(with: TestnetFaucet.webURL)
        present(safariViewController, animated: true)
    }
    private func dashDEXAction() {
        DSAuthenticationManager.sharedInstance().authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            alertIfLockout: true
        ) { [weak self] authenticated, _, _ in
            guard authenticated else { return }
            self?.dashDEXActionAuthenticated()
        }
    }

    private func dashDEXActionAuthenticated() {
        let controller = SwapKitPortalViewController()
        controller.hidesBottomBarWhenPushed = true
        let navigationController = BaseNavigationController(rootViewController: controller)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
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
        let hostingController = UIHostingController(rootView: shortcutSelectionSheetView(for: position))
        present(hostingController, animated: true)
    }

    private func shortcutSelectionSheetView(for position: Int) -> AnyView {
        let usedTypes = Set(HomeViewModel.shared.shortcutItems.map { $0.type })
        let sheet = BottomSheet(title: NSLocalizedString("Select option", comment: ""),
                                showBackButton: .constant(false)) {
            ShortcutSelectionView(usedTypes: usedTypes) { [weak self] selectedType in
                self?.applyShortcutCustomization(type: selectedType, at: position)
            }
        }

        if #available(iOS 16.4, *) {
            return AnyView(
                sheet
                    .presentationDetents([.large])
                    .presentationBackground(Color.dash.primaryBackground)
                    .presentationCornerRadius(32)
                    .presentationDragIndicator(.hidden)
            )
        } else if #available(iOS 16.0, *) {
            return AnyView(sheet.presentationDetents([.large]))
        } else {
            return AnyView(sheet)
        }
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

}
