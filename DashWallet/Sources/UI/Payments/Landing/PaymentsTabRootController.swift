//
//  Created by Roman Chornyi
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

import UIKit

/// Root of the payments tab, and the reason the landing is not built at launch.
///
/// `PaymentsLandingHostingController.init` constructs three view models that
/// read the wallet — balances over the FFI, a derived receive address, the sync
/// monitor. Making the landing the tab's root directly would run all of that
/// during `configureControllers()`, before the user has gone anywhere near
/// payments (and again on every DashPay tab reconfiguration). This container
/// defers it to `viewDidLoad`, which UIKit only runs when the tab is first
/// shown.
final class PaymentsTabRootController: UIViewController {

    private var landingController: PaymentsLandingHostingController?
    /// A tab requested before the landing existed — applied on load. Shortcut
    /// entry points select this tab and name a sub-tab in the same turn, which
    /// can be the very first time the tab is shown.
    private var pendingTab: PaymentsLandingTab?

    /// Puts the landing on `tab`, or remembers it if the landing has not been
    /// built yet.
    func select(tab: PaymentsLandingTab) {
        guard let landingController else {
            pendingTab = tab
            return
        }
        landingController.select(tab: tab)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .dw_background()

        let landing = PaymentsLandingHostingController(
            activeTab: pendingTab ?? .send,
            showsHeader: false)
        pendingTab = nil
        landingController = landing

        addChild(landing)
        landing.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(landing.view)
        NSLayoutConstraint.activate([
            // Full bounds, not the safe area: the landing hosts SwiftUI, which
            // applies the safe-area inset itself. Pinning to the guide here
            // would count the status bar twice.
            landing.view.topAnchor.constraint(equalTo: view.topAnchor),
            landing.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            landing.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            landing.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        landing.didMove(toParent: self)
    }
}

// MARK: - NavigationBarDisplayable

/// The payments tab has no navigation bar: the landing draws its own tab
/// selector at the top and nothing above it.
///
/// `MainTabbarController` already sets `isNavigationBarHidden` on the
/// navigation controller, but that only holds until the first appearance:
/// `BaseNavigationController`'s `willShow` pass re-derives it per controller
/// and falls back to SHOWING the bar for anything that does not declare
/// otherwise. The bar it then put back carried no title and no back button, so
/// it read as an unexplained ~44pt gap above the selector rather than as a bar.
extension PaymentsTabRootController: NavigationBarDisplayable {
    var isBackButtonHidden: Bool { true }
    var isNavigationBarHidden: Bool { true }
}
