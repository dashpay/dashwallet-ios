//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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
import DashUIKit
import UIKit

struct ExploreMenuScreen: View {
    private let vc: UINavigationController
    private let showBackButton: Bool
    private let onShowSendPayment: () -> Void
    private let onShowReceivePayment: () -> Void
    private let onShowGiftCard: (Data) -> Void
    private let isTestnetProvider: () -> Bool
    private let receiveAddressProvider: () -> String?

    var shouldShowGetTestDash: Bool {
        isTestnetProvider()
    }

    init(vc: UINavigationController,
         showBackButton: Bool = true,
         onShowSendPayment: @escaping () -> Void,
         onShowReceivePayment: @escaping () -> Void,
         onShowGiftCard: @escaping (Data) -> Void,
         isTestnetProvider: @escaping () -> Bool = { WalletEnvironment.isTestnet },
         receiveAddressProvider: @escaping () -> String? = { SwiftDashSDKReceiveAddressReader.receiveAddress() }) {
        self.vc = vc
        self.showBackButton = showBackButton
        self.onShowSendPayment = onShowSendPayment
        self.onShowReceivePayment = onShowReceivePayment
        self.onShowGiftCard = onShowGiftCard
        self.isTestnetProvider = isTestnetProvider
        self.receiveAddressProvider = receiveAddressProvider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showBackButton {
                DashUIKit.NavigationBar(leading: {
                    DashUIKit.NavigationBarElement.back.button {
                        vc.popViewController(animated: true)
                    }
                })
            }

            TopIntro(
                title: NSLocalizedString("Explore Dash", comment: ""),
                subtitle: NSLocalizedString("Find merchants who accept Dash and where to buy it.", comment: "")
            )
            .padding(.leading, 20)
            .padding(.trailing, 60)
            .padding(.top, 10)
            .padding(.bottom, 20)

            // Menu list
            VStack(spacing: 2) {
                if shouldShowGetTestDash {
                    MenuItem(
                        title: NSLocalizedString("Get Test Dash", comment: ""),
                        subtitle: NSLocalizedString("Test Dash is free and can be obtained from what is called a faucet.", comment: ""),
                        icon: .custom("dashCurrency", maxHeight: 30),
                        action: { getTestDashAction() }
                    )
                    .frame(minHeight: 56)
                }

                MenuItem(
                    title: NSLocalizedString("Buy & Sell Dash", comment: ""),
                    subtitle: NSLocalizedString("Select a service to buy, sell, convert and transfer Dash", comment: "Buy Sell Dash"),
                    icon: .custom("image.buy.and.sell", maxHeight: 30),
                    action: { showBuySellPortal() }
                )
                .frame(minHeight: 56)

                MenuItem(
                    title: NSLocalizedString("Where to Spend?", comment: ""),
                    subtitle: NSLocalizedString("Find merchants that accept Dash payments", comment: ""),
                    icon: .custom("image-menu-merchant", maxHeight: 30),
                    action: { showWhereToSpend() }
                )
                .frame(minHeight: 56)

                MenuItem(
                    title: NSLocalizedString("Username Marketplace", comment: "Username marketplace"),
                    subtitle: NSLocalizedString("Buy, sell and transfer DashPay usernames", comment: "Username marketplace: Explore row subtitle"),
                    icon: .system("at.circle.fill"),
                    action: { showUsernameMarketplace() }
                )
                .frame(minHeight: 56)

                MenuItem(
                    title: NSLocalizedString("ATMs", comment: ""),
                    subtitle: NSLocalizedString("Find ATMs where you can buy or sell Dash", comment: ""),
                    icon: .custom("image-menu-atm", maxHeight: 30),
                    action: { showAtms() }
                )
                .frame(minHeight: 56)

            }
            .padding(6)
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
    }

    private func getTestDashAction() {
        if let paymentAddress = currentTestDashReceiveAddress() {
            UIPasteboard.general.string = paymentAddress
        }
        if let url = URL(string: "http://faucet.testnet.networks.dash.org/") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    func currentTestDashReceiveAddress() -> String? {
        receiveAddressProvider()
    }

    private func showWhereToSpend() {
        if UserDefaults.standard.bool(forKey: kMerchantTypesShown) != true {
            let hostingController = UIHostingController(rootView: MerchantTypesDialog {
                UserDefaults.standard.setValue(true, forKey: kMerchantTypesShown)
                showMerchants()
            })
            hostingController.setDetent(640)
            vc.present(hostingController, animated: true)
        } else {
            showMerchants()
        }
    }

    private func showMerchants() {
        let merchantVC = MerchantListViewController()
        merchantVC.payWithDashHandler = { onShowSendPayment() }
        merchantVC.onGiftCardPurchased = { txId in
            vc.popToRootViewController(animated: false)
            onShowGiftCard(txId)
        }
        vc.pushViewController(merchantVC, animated: true)
    }

    /// Same auth gate the row carried in the More menu — the portal
    /// exposes account-linked balances (Coinbase/Uphold), so it stays
    /// behind PIN/biometrics wherever it is reached from.
    private func showBuySellPortal() {
        AuthenticationService.shared.authenticate(
            withPrompt: nil,
            usingBiometricAuthentication: DWGlobalOptions.sharedInstance().biometricAuthEnabled,
            alertIfLockout: true
        ) { authenticated, _, _ in
            guard authenticated else { return }
            let controller = BuySellPortalViewController.controller()
            controller.hidesBottomBarWhenPushed = true
            vc.pushViewController(controller, animated: true)
        }
    }

    private func showUsernameMarketplace() {
        let controller = UIHostingController(
            rootView: UsernameMarketplaceScreen(vc: vc))
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }

    private func showAtms() {
        let atmVC = AtmListViewController()
        atmVC.payWithDashHandler = { onShowReceivePayment() }
        atmVC.sellDashHandler = { onShowSendPayment() }
        vc.pushViewController(atmVC, animated: true)
    }
}
