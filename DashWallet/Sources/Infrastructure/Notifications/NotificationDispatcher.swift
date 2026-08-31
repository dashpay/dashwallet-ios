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
import UserNotifications

/// The only component that turns an `AppNotification` into a scheduled
/// `UNNotificationRequest`. Every feature posts through here, so permission
/// gating, dedup, grouping, and the badge number are applied in one place.
final class NotificationDispatcher {
    private let client: UserNotificationCenterClient
    private let store: NotifiedEventStoring
    private let permissions: NotificationPermissionCoordinator

    init(client: UserNotificationCenterClient,
         store: NotifiedEventStoring,
         permissions: NotificationPermissionCoordinator) {
        self.client = client
        self.store = store
        self.permissions = permissions
    }

    /// Registers one `UNNotificationCategory` per topic, so every request's
    /// `categoryIdentifier` resolves. Called once from the composition root.
    /// The `system` topic carries the inactivity reminder's two actions
    /// (`InactivityReminderScheduler` schedules the request;
    /// `NotificationLifecycle.didReceive` dispatches the action identifiers
    /// back to the scheduler); no other topic defines actions yet.
    func registerCategories() {
        let inactivityActions = [
            UNNotificationAction(identifier: InactivityReminderScheduler.remindLaterActionIdentifier,
                                 title: NSLocalizedString("Remind me later", comment: "Inactivity reminder"),
                                 options: []),
            UNNotificationAction(identifier: InactivityReminderScheduler.optOutActionIdentifier,
                                 title: NSLocalizedString("Don't remind me again", comment: "Inactivity reminder"),
                                 options: []),
        ]
        let categories = Set(NotificationTopic.allCases.map { topic in
            UNNotificationCategory(identifier: topic.rawValue,
                                   actions: topic == .system ? inactivityActions : [],
                                   intentIdentifiers: [],
                                   options: [])
        })
        client.setNotificationCategories(categories)
    }

    /// Posts the event, unless the permission gate or the dedup store drops
    /// it. Returns whether a request was actually handed to the notification
    /// center — callers that mirror posted notifications elsewhere (the
    /// producers' watch bridge) key off this.
    @discardableResult
    func post(_ notification: AppNotification) async -> Bool {
        let state = await permissions.effectiveState()
        guard state == .on else {
            // Dropped before the dedup mark on purpose: for
            // `.awaitingAuthorization` (and the off/blocked states) the OS
            // would swallow the request, so consuming the id here would
            // suppress the event forever — it stays postable for the
            // post-grant catch-up scan instead.
            DWLogger.log("NotificationDispatcher: dropped \(notification.id) — permission state \(state)")
            return false
        }
        guard await store.markIfNew(id: notification.id, topic: notification.topic) else {
            DWLogger.log("NotificationDispatcher: dropped \(notification.id) — already notified")
            return false
        }
        // The just-marked event is unseen, so the count includes it.
        let unseen = await store.unseenCount()

        let content = UNMutableNotificationContent()
        if let title = notification.title {
            content.title = title
        }
        content.body = notification.body
        content.sound = notification.sound
        content.threadIdentifier = notification.topic.rawValue
        content.categoryIdentifier = notification.topic.rawValue
        // Badge truth is the store's unseen count — never incremental
        // arithmetic on `applicationIconBadgeNumber`, so
        // `NotificationLifecycle` can reconcile it to zero.
        content.badge = NSNumber(value: unseen)
        content.interruptionLevel = notification.topic == .transactions ? .timeSensitive : .active

        var userInfo: [String: Any] = [
            NotificationUserInfoKey.foregroundBehavior: notification.foregroundBehavior.rawValue,
        ]
        if let routeData = notification.route?.encodedForUserInfo() {
            userInfo[NotificationUserInfoKey.route] = routeData
        }
        content.userInfo = userInfo

        // Deliver immediately: a delayed trigger races the user's return to
        // the foreground.
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
        do {
            try await client.add(request)
            DWLogger.log("NotificationDispatcher: posted \(notification.id) (topic \(notification.topic.rawValue))")
            return true
        } catch {
            DWLogger.log("NotificationDispatcher: failed to post \(notification.id): \(error)")
            // Roll the dedup mark back: nothing was delivered, so a retry
            // post must be able to reach the center. (The mark stays before
            // `add` above — it is the concurrent-duplicate guard.)
            await store.unmark(id: notification.id)
            return false
        }
    }
}
