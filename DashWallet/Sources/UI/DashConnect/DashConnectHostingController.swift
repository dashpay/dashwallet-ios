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

    init(navigationController: UINavigationController, uri: String? = nil) {
        let viewModel = ConnectionsViewModel()
        self.viewModel = viewModel
        pendingURI = uri

        super.init(rootView: ConnectionsScreen(vc: navigationController, viewModel: viewModel))
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
