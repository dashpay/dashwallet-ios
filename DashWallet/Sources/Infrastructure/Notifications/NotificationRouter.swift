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

// MARK: - NotificationRouting

/// Seam between `NotificationLifecycle` (which decodes taps) and the
/// presentation layer, so tap handling is testable without presenting UI.
protocol NotificationRouting: AnyObject {
    @MainActor func open(_ route: DeepLinkRoute)
}

// MARK: - NotificationRouter

/// The single `DeepLinkRoute` → presentation table for notification taps.
@MainActor
final class NotificationRouter: NotificationRouting {
    /// The controller notification screens present from — the window's root,
    /// resolved at tap time.
    private let presentingController: () -> UIViewController?

    init(presentingController: @escaping () -> UIViewController?) {
        self.presentingController = presentingController
    }

    func open(_ route: DeepLinkRoute) {
        switch route {
        case .home:
            // Opening the app — which the tap already did — is the whole
            // destination: home is the root screen, nothing to present.
            break

        case .staking:
            // CrowdNode needs a synced wallet; before that, the tap just
            // opens the app.
            guard SyncingActivityMonitor.shared.state == .syncDone else { return }
            let controller = CrowdNodeModelObjcWrapper.getRootVC()
            presentingController()?.present(controller, animated: true)

        case .url(let url):
            UIApplication.shared.open(url)

        case .transactionDetail, .swapOrder, .dashPayNotifications:
            // TODO(notifications-routing): not wired to their screens yet —
            // the tap opens the app at home until the transaction-detail,
            // swap-order, and DashPay-bell presentations land.
            break
        }
    }
}
