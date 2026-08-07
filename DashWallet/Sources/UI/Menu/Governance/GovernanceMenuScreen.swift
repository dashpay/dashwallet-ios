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

import DashUIKit
import SwiftUI
import UIKit

/// Governance submenu: the wallet's masternode-facing surfaces, reached from
/// the main menu's "Governance" row. Groups Masternodes (moved here from
/// Tools) with username Voting (moved here from the main menu).
struct GovernanceMenuScreen: View {
    private let vc: UINavigationController

    @StateObject private var viewModel = GovernanceMenuViewModel()

    init(vc: UINavigationController) {
        self.vc = vc
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavBarBack {
                vc.popViewController(animated: true)
            }

            TopIntro(title: NSLocalizedString("Governance", comment: "Governance"))
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
            .background(Color.dash.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.dash.shadow, radius: 20, x: 0, y: 5)
            .padding(.horizontal, 20)

            Spacer()
        }
        .background(Color.dash.primaryBackground)
        .navigationBarHidden(true)
        .onReceive(viewModel.$navigationDestination) { destination in
            handleNavigation(destination)
        }
    }

    private func handleNavigation(_ destination: GovernanceMenuNavigationDestination?) {
        switch destination {
        case .masternodes:
            showMasternodes()
        #if DASHPAY
        case .voting:
            showVoting()
        #endif
        case .none:
            break
        }

        if destination != nil {
            viewModel.resetNavigation()
        }
    }

    /// Same hosting wrapper Tools used when this screen lived there: the
    /// SwiftUI list needs its own `NavigationStack` for row drill-downs, so
    /// the back button is wired explicitly to pop the UIKit stack.
    private func showMasternodes() {
        let navController = vc
        let popRoot: () -> Void = { [weak navController] in
            _ = navController?.popViewController(animated: true)
        }

        let hosting = UIHostingController(
            rootView: AnyView(
                NavigationStack {
                    MasternodesScreen()
                        .navigationTitle(NSLocalizedString("Masternodes", comment: "Masternodes"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button(action: popRoot) {
                                    Image(systemName: "chevron.left")
                                }
                            }
                        }
                }
            )
        )
        hosting.hidesBottomBarWhenPushed = true
        vc.pushViewController(hosting, animated: true)
    }

    #if DASHPAY
    private func showVoting() {
        let controller = UIHostingController(rootView: UsernameVotingScreen())
        controller.hidesBottomBarWhenPushed = true
        vc.pushViewController(controller, animated: true)
    }
    #endif
}
