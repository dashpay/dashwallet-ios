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

// MARK: - NotificationForegroundBehavior

/// How a notification presents while the app is frontmost. The poster
/// decides; `NotificationLifecycle.willPresent` reads it back from the
/// request's `userInfo` and obeys.
enum NotificationForegroundBehavior: String {
    /// Not shown while the app is frontmost (the app UI already shows the content).
    case suppress
    /// Shown as a banner with sound, and kept in Notification Center.
    case banner
    /// Kept in Notification Center without a banner or sound.
    case listOnly
}

// MARK: - AppNotification

/// The typed event every feature posts through `NotificationDispatcher`
/// instead of hand-building `UNMutableNotificationContent`.
struct AppNotification {
    /// Stable identifier: doubles as the `UNNotificationRequest` identifier,
    /// the `NotifiedEventStore` dedup key, and the clearing key.
    let id: String
    let topic: NotificationTopic
    let title: String?
    let body: String
    let sound: UNNotificationSound?
    let route: DeepLinkRoute?
    let foregroundBehavior: NotificationForegroundBehavior
}

// MARK: - NotificationUserInfoKey

/// Keys the dispatcher writes into `UNNotificationContent.userInfo` and
/// `NotificationLifecycle` reads back. Values must stay plist-encodable.
enum NotificationUserInfoKey {
    /// JSON-encoded `DeepLinkRoute` (`Data`).
    static let route = "org.dash.notification.route"
    /// `NotificationForegroundBehavior` raw value (`String`).
    static let foregroundBehavior = "org.dash.notification.foreground-behavior"
}
