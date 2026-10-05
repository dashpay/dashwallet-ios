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
    /// The lock screen is up; a tap that would present a screen waits for the
    /// unlock, as an incoming link does.
    private let isLocked: @MainActor () -> Bool
    /// A tap waiting for the app to become active or to be unlocked (the first
    /// one wins, as for links). Dropped when the wallet changes or is wiped.
    private var waitingRoute: DeepLinkRoute?
    private var waitObservers: [NSObjectProtocol] = []

    init(presentingController: @escaping () -> UIViewController?,
         isLocked: @escaping @MainActor () -> Bool = { WalletLifecycleOverlayPresenter.shared.lockScreenVisible }) {
        self.presentingController = presentingController
        self.isLocked = isLocked
    }

    func open(_ route: DeepLinkRoute) {
        switch route {
        case .home:
            // Opening the app — which the tap already did — is the whole
            // destination: home is the root screen, nothing to present.
            break

        case .staking:
            // Delivered before the app is active, the lock screen — if it is
            // due — is not up yet: decide once the app is active.
            if UIApplication.shared.applicationState != .active {
                wait(for: UIApplication.didBecomeActiveNotification, toOpen: route)
                return
            }
            if isLocked() {
                wait(for: Self.appDidUnlock, toOpen: route)
                return
            }
            // CrowdNode needs a synced wallet; before that, the tap just
            // opens the app.
            guard SyncingActivityMonitor.shared.state == .syncDone else { return }
            // Covering the screen is replacing it: same rule as an incoming
            // link — not over a payment or anything presented.
            guard let root = presentingController(),
                  !PaymentInFlight.refuses(.navigation, over: root) else { return }
            let controller = CrowdNodeModelObjcWrapper.getRootVC()
            root.present(controller, animated: true)

        case .url(let url):
            UIApplication.shared.open(url)

        case .transactionDetail, .swapOrder, .dashPayNotifications:
            // TODO(notifications-routing): not wired to their screens yet —
            // the tap opens the app at home until the transaction-detail,
            // swap-order, and DashPay-bell presentations land.
            break
        }
    }

    private func wait(for event: Notification.Name, toOpen route: DeepLinkRoute) {
        guard waitingRoute == nil else { return }
        waitingRoute = route
        let center = NotificationCenter.default
        waitObservers = [
            center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let route = self.endWait() else { return }
                    // After the root has handled the same event (the lock
                    // screen shows on activation).
                    DispatchQueue.main.async { self.open(route) }
                }
            },
            center.addObserver(
                forName: SwiftDashSDKWalletState.activeWalletDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                // Wiped or switched: the tap was for the wallet that is gone.
                MainActor.assumeIsolated { _ = self?.endWait() }
            },
        ]
    }

    private func endWait() -> DeepLinkRoute? {
        let route = waitingRoute
        waitingRoute = nil
        waitObservers.forEach { NotificationCenter.default.removeObserver($0) }
        waitObservers = []
        return route
    }

    /// `DWAppDidUnlockNotification`, posted by the root once the lock screen
    /// has gone.
    static let appDidUnlock = Notification.Name("DWAppDidUnlockNotification")
}
