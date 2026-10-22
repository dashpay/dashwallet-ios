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
/// `dash-key:` / `dash-st:` request that arrives while the screen is already
/// on the stack is routed into it instead of pushing a second copy.
final class DashConnectHostingController: UIHostingController<ConnectionsScreen> {
    private let viewModel: ConnectionsViewModel
    /// Held until `viewDidAppear`: the approval sheet is presented from the
    /// screen, which cannot present while it is still being pushed.
    private var pendingURI: String?
    /// Whether `pendingURI` was read off a QR code rather than opened as a
    /// link. A scanned code goes in as a scan, the way the screen's own
    /// scanner hands one over.
    private var pendingURIWasScanned = false

    init(navigationController: UINavigationController, uri: String? = nil, scanned: Bool = false) {
        let viewModel = ConnectionsViewModel()
        self.viewModel = viewModel
        pendingURI = uri
        pendingURIWasScanned = scanned

        super.init(rootView: ConnectionsScreen(vc: navigationController, viewModel: viewModel))
    }

    @MainActor dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        consumePendingURI()
    }

    /// Handles a request that arrived for a screen that is already on the
    /// stack: a link, or with `scanned` a code another screen's scanner read.
    func handle(uri: String, scanned: Bool = false) {
        pendingURI = uri
        pendingURIWasScanned = scanned

        if isViewLoaded, view.window != nil {
            consumePendingURI()
        }
    }

    private func consumePendingURI() {
        guard let uri = pendingURI else { return }
        pendingURI = nil
        if pendingURIWasScanned {
            viewModel.onQRScanned(uri)
        } else {
            viewModel.onURIReceived(uri)
        }
    }
}
