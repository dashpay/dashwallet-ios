//
//  SyncInfoMenuScreen.swift
//  DashWallet
//
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
//  Main-menu "Sync Info" category: hosts the SwiftDashSDK sync diagnostics
//  (L1 SPV, Platform/BLAST, DashPay, Shielded) that previously lived under
//  Tools. Mirrors the SwiftExampleApp "Sync Status" tab's four sections.
//

import SwiftUI
import UIKit

struct SyncInfoMenuScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel = SyncInfoMenuViewModel()

    init(vc: UINavigationController) {
        self.vc = vc
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(title: NSLocalizedString("Sync Info", comment: ""))
                .padding(.leading, 20)
                .padding(.trailing, 60)
                .padding(.top, 10)
                .padding(.bottom, 20)

            VStack(spacing: 2) {
                ForEach(viewModel.items) { item in
                    MenuItem(
                        title: item.title,
                        subtitle: item.subtitle,
                        details: item.details,
                        icon: item.icon,
                        showInfo: item.showInfo,
                        showChevron: false,
                        isToggled: item.isToggled,
                        action: item.action
                    )
                    .frame(minHeight: 56)
                }
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
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
    }

    private func handleNavigation(_ destination: SyncInfoMenuNavigationDestination?) {
        switch destination {
        case .swiftDashSDKSPVStatus:
            push(SwiftDashSDKSPVStatusScreen(vc: vc))
        case .platformSyncStatus:
            push(PlatformSyncStatusScreen(vc: vc))
        #if DASHPAY
        case .dashPaySyncInfo:
            push(DashPaySyncInfoScreen(vc: vc))
        #endif
        case .shieldedSyncInfo:
            push(ShieldedSyncInfoScreen(vc: vc))
        case .none:
            break
        }

        if destination != nil {
            viewModel.resetNavigation()
        }
    }

    private func push<Content: View>(_ screen: Content) {
        let hosting = UIHostingController(rootView: screen)
        hosting.hidesBottomBarWhenPushed = true
        vc.pushViewController(hosting, animated: true)
    }
}
