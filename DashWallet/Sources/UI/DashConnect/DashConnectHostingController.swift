//
//  DashConnectHostingController.swift
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

import SwiftUI
import UIKit

/// Hosts `ConnectionsScreen` and keeps a handle on its view model, so a
/// `dash-key:` / `dash-st:` link that arrives while the screen is already on
/// the stack is routed into it instead of pushing a second copy.
final class DashConnectHostingController: UIHostingController<ConnectionsScreen> {
    private let viewModel: ConnectionsViewModel
    /// Held until `viewDidAppear`: the approval sheet is presented from the
    /// screen, which cannot present while it is still being pushed.
    private var pendingURI: String?

    /// `dashPayModel` tells whether the wallet has a username and starts
    /// creating one; without it the page does not ask. `viewModel` is for
    /// tests.
    init(
        navigationController: UINavigationController,
        uri: String? = nil,
        dashPayModel: DWDashPayProtocol? = nil,
        viewModel: ConnectionsViewModel? = nil
    ) {
        let viewModel = viewModel ?? ConnectionsViewModel(
            usernameState: { dashPayModel == nil ? .present : Self.activeIdentityUsernameState() })
        self.viewModel = viewModel
        pendingURI = uri

        super.init(rootView: ConnectionsScreen(
            vc: navigationController,
            viewModel: viewModel,
            onCreateUsername: Self.createUsername(on: navigationController, dashPayModel: dashPayModel),
            onTopUpIdentity: Self.topUp(over: navigationController)))
    }

    /// Whether the active identity owns a username. `registrationCompleted`
    /// is not asked: it is one flag for every wallet on the network, so
    /// another wallet's name would count. Until the identity's names are
    /// read the answer is unknown: no login is approved, and the user is
    /// not asked to create a name they may have.
    @MainActor
    private static func activeIdentityUsernameState() -> ConnectionsViewModel.UsernameState {
        #if DASHPAY
        let identity = DWCurrentUserIdentityInfo.shared.refreshedSnapshot()
        guard identity.hasIdentity else { return .missing }
        guard identity.namesAreLoaded else { return .unknown }
        return identity.usernames.isEmpty ? .missing : .present
        #else
        return .present
        #endif
    }

    private static func createUsername(
        on navigationController: UINavigationController,
        dashPayModel: DWDashPayProtocol?
    ) -> (() -> Void)? {
        #if DASHPAY
        guard let dashPayModel else { return nil }
        return { [weak navigationController] in
            guard let navigationController else { return }
            MainMenuScreen.pushCreateUsernameForm(on: navigationController, dashPayModel: dashPayModel)
        }
        #else
        return nil
        #endif
    }

    /// The identity top-up, over the approve sheet. The refused request is
    /// not approved again; the app gives a new code once the balance is
    /// there. `nil` in a build without DashPay, which has no top-up.
    private static func topUp(over navigationController: UINavigationController) -> (() -> Void)? {
        #if DASHPAY
        return { [weak navigationController] in
            guard let navigationController else { return }
            var presenter: UIViewController = navigationController
            while let presented = presenter.presentedViewController { presenter = presented }
            presenter.present(IdentityCreditGate.makeTopUpController(), animated: true)
        }
        #else
        return nil
        #endif
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        consumePendingURI()
    }

    /// Opens a DashConnect link on the Connections screen of the More tab:
    /// the one on top of `menuNav`, or a new one (`makeScreen`) pushed there.
    ///
    /// Only a new screen clears what `tabBar` presents. The open screen
    /// decides that itself (`handle(uri:)`): dismissing from here closed its
    /// approval sheet behind SwiftUI's back, and the screen then refused
    /// every scan until it was left (#1517).
    static func route(
        _ uri: String,
        tabBar: UITabBarController,
        menuNav: UINavigationController,
        moreTabIndex: Int?,
        makeScreen: () -> DashConnectHostingController
    ) {
        let scheme = uri.prefix { $0 != ":" }

        if let connections = menuNav.topViewController as? DashConnectHostingController {
            DWLogger.log("🔗 DASHCONNECT :: link (\(scheme)) to the open Connections screen")
            if let moreTabIndex {
                tabBar.selectedIndex = moreTabIndex
            }
            connections.handle(uri: uri)
            return
        }

        DWLogger.log("🔗 DASHCONNECT :: link (\(scheme)) opens Connections")
        tabBar.dismiss(animated: false, completion: nil)
        if let moreTabIndex {
            tabBar.selectedIndex = moreTabIndex
        }
        menuNav.pushViewController(makeScreen(), animated: true)
    }

    /// Handles a link that arrived for a screen that is already on the stack.
    ///
    /// A sheet of the screen's own stays up and answers the link: closed
    /// from UIKit, SwiftUI never hears of it, so the model would keep a
    /// request nobody sees and refuse every scan after it. Anything else
    /// over the screen (the scanner, another flow's screen, an alert) is
    /// closed first, so the request can show.
    func handle(uri: String) {
        pendingURI = uri

        guard isViewLoaded, view.window != nil else { return }

        // What covers the screen is presented over the tab bar.
        let presenter: UIViewController = tabBarController ?? self
        if viewModel.showsOwnSheet || presenter.presentedViewController == nil {
            consumePendingURI()
            return
        }

        presenter.dismiss(animated: false) { [weak self] in
            // The page's alert, if that was it, is gone now.
            self?.viewModel.message = nil
            self?.consumePendingURI()
        }
    }

    private func consumePendingURI() {
        guard let uri = pendingURI else { return }
        pendingURI = nil
        viewModel.onURIReceived(uri)
    }
}
