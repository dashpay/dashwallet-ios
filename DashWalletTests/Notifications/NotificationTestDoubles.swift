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
@testable import dashwallet

// MARK: - FakeUserNotificationCenterClient

final class FakeUserNotificationCenterClient: UserNotificationCenterClient {
    var authorizationStatusValue: UNAuthorizationStatus = .authorized
    var requestAuthorizationResult: Result<Bool, Error> = .success(true)
    var deliveredSummaries: [DeliveredNotificationSummary] = []

    private(set) var addedRequests: [UNNotificationRequest] = []
    private(set) var removedDeliveredIdentifiers: [[String]] = []
    private(set) var removedPendingIdentifiers: [[String]] = []
    private(set) var badgeCounts: [Int] = []
    private(set) var registeredCategorySets: [Set<UNNotificationCategory>] = []
    private(set) var requestedAuthorizationOptions: [UNAuthorizationOptions] = []

    var onSetBadgeCount: ((Int) -> Void)?

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func deliveredNotificationSummaries() async -> [DeliveredNotificationSummary] {
        deliveredSummaries
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        removedDeliveredIdentifiers.append(identifiers)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedPendingIdentifiers.append(identifiers)
    }

    func setBadgeCount(_ count: Int) {
        badgeCounts.append(count)
        onSetBadgeCount?(count)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        authorizationStatusValue
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestedAuthorizationOptions.append(options)
        return try requestAuthorizationResult.get()
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        registeredCategorySets.append(categories)
    }
}

// MARK: - InMemoryNotifiedEventStore

final class InMemoryNotifiedEventStore: NotifiedEventStoring {
    struct Event {
        let topic: NotificationTopic
        var seen: Bool
    }

    private(set) var events: [String: Event] = [:]
    private(set) var markAllSeenTopics: [NotificationTopic] = []

    func seed(id: String, topic: NotificationTopic, seen: Bool = false) {
        events[id] = Event(topic: topic, seen: seen)
    }

    func markIfNew(id: String, topic: NotificationTopic) async -> Bool {
        if events[id] != nil {
            return false
        }
        events[id] = Event(topic: topic, seen: false)
        return true
    }

    func consume(id: String, topic: NotificationTopic) async {
        if events[id] == nil {
            events[id] = Event(topic: topic, seen: true)
        }
    }

    func unseenCount() async -> Int {
        events.values.filter { !$0.seen }.count
    }

    func markAllSeen(topic: NotificationTopic) async {
        markAllSeenTopics.append(topic)
        for (id, event) in events where event.topic == topic {
            events[id]?.seen = true
        }
    }
}

// MARK: - FakeNotificationPreferenceStore

final class FakeNotificationPreferenceStore: NotificationPreferenceStore {
    var userWantsNotifications = true
}

// MARK: - RecordingNotificationRouter

@MainActor
final class RecordingNotificationRouter: NotificationRouting {
    private(set) var openedRoutes: [DeepLinkRoute] = []

    func open(_ route: DeepLinkRoute) {
        openedRoutes.append(route)
    }
}
