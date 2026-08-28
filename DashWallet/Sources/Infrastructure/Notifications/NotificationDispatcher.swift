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
    /// No topic defines actions yet; the categories are registered without
    /// any, and actions are added here together with the features that
    /// handle them.
    func registerCategories() {
        let categories = Set(NotificationTopic.allCases.map {
            UNNotificationCategory(identifier: $0.rawValue,
                                   actions: [],
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
            return false
        }
    }
}
