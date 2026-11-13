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
    /// creating one; without it the page does not ask.
    init(navigationController: UINavigationController, uri: String? = nil, dashPayModel: DWDashPayProtocol? = nil) {
        let viewModel = ConnectionsViewModel(
            hasUsername: { dashPayModel == nil || Self.activeIdentityHasUsername() })
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
    /// read it is not asked to create one.
    @MainActor
    private static func activeIdentityHasUsername() -> Bool {
        #if DASHPAY
        let identity = DWCurrentUserIdentityInfo.shared.refreshedSnapshot()
        guard identity.hasIdentity else { return false }
        return !identity.usernames.isEmpty || !identity.namesAreLoaded
        #else
        return true
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

    /// The identity top-up, over the approve sheet: the request stays on
    /// screen to be approved once the balance is there. `nil` in a build
    /// without DashPay, which has no top-up.
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

    /// Handles a link that arrived for a screen that is already on the stack.
    func handle(uri: String) {
        pendingURI = uri

        if isViewLoaded, view.window != nil {
            consumePendingURI()
        }
    }

    private func consumePendingURI() {
        guard let uri = pendingURI else { return }
        pendingURI = nil
        viewModel.onURIReceived(uri)
    }
}
