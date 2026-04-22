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

import UIKit
import SwiftUI

private let kMerchantTypesShownKey = "merchantTypesInfoDialogShownKey"

struct ExploreMenuScreen: View {
    private let vc: UINavigationController
    private let showBackButton: Bool
    private let onShowSendPayment: () -> Void
    private let onShowReceivePayment: () -> Void
    private let onShowGiftCard: (Data) -> Void

    @State private var showSyncingAlert = false

    private var isTestnet: Bool {
        DWEnvironment.sharedInstance().currentChain.isTestnet()
    }

    init(vc: UINavigationController,
         showBackButton: Bool = true,
         onShowSendPayment: @escaping () -> Void,
         onShowReceivePayment: @escaping () -> Void,
         onShowGiftCard: @escaping (Data) -> Void) {
        self.vc = vc
        self.showBackButton = showBackButton
        self.onShowSendPayment = onShowSendPayment
        self.onShowReceivePayment = onShowReceivePayment
        self.onShowGiftCard = onShowGiftCard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showBackButton {
                NavBarBack {
                    vc.popViewController(animated: true)
                }
            }

            TopIntro(
                title: NSLocalizedString("Explore Dash", comment: ""),
                subtitle: NSLocalizedString("Find merchants that accept Dash, where to buy it and how to earn income with it.", comment: "")
            )

            // Menu list
            VStack(spacing: 2) {
                if isTestnet {
                    MenuItem(
                        title: NSLocalizedString("Get Test Dash", comment: ""),
                        subtitle: NSLocalizedString("Test Dash is free and can be obtained from what is called a faucet.", comment: ""),
                        icon: .custom("dashCurrency", maxHeight: 30),
                        action: { getTestDashAction() }
                    )
                    .frame(minHeight: 56)
                }

                MenuItem(
                    title: NSLocalizedString("Where to Spend?", comment: ""),
                    subtitle: NSLocalizedString("Find merchants that accept Dash payments", comment: ""),
                    icon: .custom("image-menu-merchant", maxHeight: 30),
                    action: { showWhereToSpend() }
                )
                .frame(minHeight: 56)

                MenuItem(
                    title: NSLocalizedString("ATMs", comment: ""),
                    subtitle: NSLocalizedString("Find ATMs where you can buy or sell Dash", comment: ""),
                    icon: .custom("image-menu-atm", maxHeight: 30),
                    action: { showAtms() }
                )
                .frame(minHeight: 56)

                MenuItem(
                    title: NSLocalizedString("Staking", comment: ""),
                    subtitleView: AnyView(StakingSubtitle()),
                    icon: .custom("image-menu-staking", maxHeight: 30),
                    iconAlignment: .top,
                    action: { showStaking() }
                )
                .frame(minHeight: 56)
            }
            .padding(6)
            .background(Color.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.primaryBackground)
        .navigationBarHidden(true)
        .alert(NSLocalizedString("The chain is syncing…", comment: ""), isPresented: $showSyncingAlert) {
            Button(NSLocalizedString("Go to CrowdNode website", comment: "")) {
                UIApplication.shared.open(CrowdNodeObjcWrapper.crowdNodeWebsiteUrl(), options: [:], completionHandler: nil)
            }
            Button(NSLocalizedString("Close", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("Wait until the chain is fully synced, so we can review your transaction history. Visit CrowdNode website to log in or sign up.", comment: ""))
        }
    }

    @ViewBuilder
    private func StakingSubtitle() -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(NSLocalizedString("Easily stake Dash and earn passive income with a few simple clicks", comment: ""))
                .font(.footnote)
                .foregroundColor(.tertiaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            CrowdNodeAPYBadge()
                .frame(height: 24)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func getTestDashAction() {
        let account = DWEnvironment.sharedInstance().currentAccount
        if let paymentAddress = account.receiveAddress {
            UIPasteboard.general.string = paymentAddress
        }
        if let url = URL(string: "http://faucet.testnet.networks.dash.org/") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func showWhereToSpend() {
        if UserDefaults.standard.bool(forKey: kMerchantTypesShownKey) != true {
            let hostingController = UIHostingController(rootView: MerchantTypesDialog {
                UserDefaults.standard.setValue(true, forKey: kMerchantTypesShownKey)
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

    private func showAtms() {
        let atmVC = AtmListViewController()
        atmVC.payWithDashHandler = { onShowReceivePayment() }
        atmVC.sellDashHandler = { onShowSendPayment() }
        vc.pushViewController(atmVC, animated: true)
    }

    private func showStaking() {
        if SyncingActivityMonitor.shared.state == .syncDone {
            let stakingVC = CrowdNodeModelObjcWrapper.getRootVC()
            vc.pushViewController(stakingVC, animated: true)
        } else {
            showSyncingAlert = true
        }
    }
}

struct CrowdNodeAPYBadge: View {
    private static let systemGreen = Color(red: 98/255, green: 182/255, blue: 125/255)

    private var apy: String {
        let apyValue = CrowdNode.shared.crowdnodeAPY
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .percent
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.multiplier = 1
        return numberFormatter.string(from: NSNumber(value: apyValue)) ?? ""
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(String.localizedStringWithFormat(NSLocalizedString("Current APY = %@", comment: "CrowdNode"), apy))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Self.systemGreen)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Self.systemGreen.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
