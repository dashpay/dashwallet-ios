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

import Foundation
import UIKit
import UserNotifications

/// Owns the `UNUserNotificationCenterDelegate` role and notification
/// clearing: foreground presentation, tap routing, and the become-active
/// reconciliation (badge to zero, delivered transaction notifications
/// removed, store marked seen). Observes
/// `UIApplication.didBecomeActiveNotification` itself — `AppDelegate` only
/// constructs it and assigns it as the center's delegate.
@MainActor
final class NotificationLifecycle: NSObject {
    /// The identifier older builds delivered every transaction notification
    /// under; removed on activation so upgraders don't keep a stale banner.
    nonisolated static let legacyTransactionIdentifier = "Now"

    /// Presentation for notifications whose `userInfo` carries no
    /// `NotificationForegroundBehavior` — anything delivered by an older
    /// build or posted outside the dispatcher. Matches the previous
    /// `AppDelegate` delegate behavior.
    nonisolated static let defaultPresentationOptions: UNNotificationPresentationOptions = [.list, .banner, .sound]

    private let client: UserNotificationCenterClient
    private let store: NotifiedEventStoring
    private let router: NotificationRouting
    private var didBecomeActiveObserver: NSObjectProtocol?

    /// Target of the inactivity reminder's category actions. Weak and
    /// settable: the composition root owns the scheduler and wires it in
    /// after both objects exist.
    weak var inactivityReminderHandler: InactivityReminderActionHandling?

    init(client: UserNotificationCenterClient,
         store: NotifiedEventStoring,
         router: NotificationRouting) {
        self.client = client
        self.store = store
        self.router = router
        super.init()

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.reconcileAfterBecomingActive() }
        }
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    // MARK: Handlers

    /// Become-active reconciliation: the app now shows the transactions
    /// feed, so the badge and the delivered transaction notifications are
    /// stale. Other threads (CrowdNode, announcements) stay until acted on.
    func reconcileAfterBecomingActive() async {
        client.setBadgeCount(0)
        await clearTray(topic: .transactions, extraIdentifiers: [Self.legacyTransactionIdentifier])
    }

    #if DASHPAY
    /// Bell-screen exit reconciliation: the user has just viewed the
    /// DashPay notifications screen, so the tray's dashpay thread and the
    /// store's dashpay seen-state are stale. Reached through the
    /// `SwiftDashSDKContactsService.notificationsViewedHandler` seam the
    /// composition root injects — the bell and the tray share one
    /// seen-state, so viewing either surface clears both. Idempotent; the
    /// badge is untouched (this is not an activation, and the become-active
    /// pass already zeroed it).
    func reconcileAfterDashPayNotificationsViewed() async {
        await clearTray(topic: .dashpay)
    }
    #endif

    /// Removes the delivered notifications on `topic`'s thread (plus any
    /// `extraIdentifiers` regardless of thread — legacy identifiers
    /// delivered by older builds) and marks the topic seen in the store.
    private func clearTray(topic: NotificationTopic, extraIdentifiers: Set<String> = []) async {
        let thread = topic.rawValue
        let delivered = await client.deliveredNotificationSummaries()
        let identifiers = delivered
            .filter { $0.threadIdentifier == thread || extraIdentifiers.contains($0.identifier) }
            .map(\.identifier)
        if !identifiers.isEmpty {
            client.removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        await store.markAllSeen(topic: topic)
    }

    /// Presentation options for a notification arriving while the app is
    /// frontmost, from the behavior its poster encoded into `userInfo`.
    nonisolated static func presentationOptions(forUserInfo userInfo: [AnyHashable: Any]) -> UNNotificationPresentationOptions {
        guard let raw = userInfo[NotificationUserInfoKey.foregroundBehavior] as? String,
              let behavior = NotificationForegroundBehavior(rawValue: raw) else {
            return defaultPresentationOptions
        }
        switch behavior {
        case .suppress:
            return []
        case .banner:
            return [.list, .banner, .sound]
        case .listOnly:
            return [.list]
        }
    }

    /// Response handling: the inactivity reminder's category actions go to
    /// their handler by action identifier; the default tap action (and any
    /// identifier this build doesn't know) routes as a plain tap.
    func handleNotificationResponse(actionIdentifier: String,
                                    identifier: String,
                                    userInfo: [AnyHashable: Any]) {
        switch actionIdentifier {
        case InactivityReminderScheduler.remindLaterActionIdentifier:
            inactivityReminderHandler?.handleRemindLater()
        case InactivityReminderScheduler.optOutActionIdentifier:
            inactivityReminderHandler?.handleOptOut()
        default:
            handleNotificationTap(identifier: identifier, userInfo: userInfo)
        }
    }

    /// Tap handling: decode the route and hand it to the router. The legacy
    /// CrowdNode identifier predates encoded routes and folds into
    /// `.staking`, keeping the old `AppDelegate` special case working for
    /// already-delivered notifications.
    func handleNotificationTap(identifier: String, userInfo: [AnyHashable: Any]) {
        var route = DeepLinkRoute.decode(fromUserInfo: userInfo)
        if route == nil, identifier == CrowdNode.notificationID {
            route = .staking
        }
        guard let route else { return }
        router.open(route)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationLifecycle: UNUserNotificationCenterDelegate {
    // Both delegate methods call their completion handler unconditionally on
    // every path — returning without it makes iOS drop the notification
    // after a delegate timeout. They stay one-expression trampolines over
    // the handlers above (`UNNotification`/`UNNotificationResponse` cannot
    // be constructed in tests, the handlers can be exercised directly).

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(Self.presentationOptions(forUserInfo: notification.request.content.userInfo))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let actionIdentifier = response.actionIdentifier
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            self.handleNotificationResponse(actionIdentifier: actionIdentifier,
                                            identifier: identifier,
                                            userInfo: userInfo)
        }
        completionHandler()
    }
}
