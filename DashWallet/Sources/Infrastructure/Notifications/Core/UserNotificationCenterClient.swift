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

// MARK: - DeliveredNotificationSummary

/// The identifier/thread pair of a delivered notification. `UNNotification`
/// has no public initializer, so the client seam trades in this value
/// instead — fakes can construct it.
struct DeliveredNotificationSummary: Equatable {
    let identifier: String
    let threadIdentifier: String
}

// MARK: - UserNotificationCenterClient

/// Protocol seam over `UNUserNotificationCenter`: exactly the calls the
/// notifications module makes, so tests can substitute a fake.
protocol UserNotificationCenterClient: AnyObject {
    func add(_ request: UNNotificationRequest) async throws
    func deliveredNotificationSummaries() async -> [DeliveredNotificationSummary]
    func removeDeliveredNotifications(withIdentifiers identifiers: [String])
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func setBadgeCount(_ count: Int)
    /// Read live from the OS on every call — authorization is never cached.
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

// MARK: - SystemUserNotificationCenterClient

/// The production client: a thin pass-through to
/// `UNUserNotificationCenter.current()`.
final class SystemUserNotificationCenterClient: UserNotificationCenterClient {
    private var center: UNUserNotificationCenter { .current() }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func deliveredNotificationSummaries() async -> [DeliveredNotificationSummary] {
        await center.deliveredNotifications().map {
            DeliveredNotificationSummary(identifier: $0.request.identifier,
                                         threadIdentifier: $0.request.content.threadIdentifier)
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func setBadgeCount(_ count: Int) {
        center.setBadgeCount(count, withCompletionHandler: nil)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }
}
