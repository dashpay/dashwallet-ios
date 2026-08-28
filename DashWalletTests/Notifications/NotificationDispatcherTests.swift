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

import XCTest
import UserNotifications
@testable import dashwallet

final class NotificationDispatcherTests: XCTestCase {
    private var client: FakeUserNotificationCenterClient!
    private var store: InMemoryNotifiedEventStore!
    private var preferences: FakeNotificationPreferenceStore!
    private var dispatcher: NotificationDispatcher!

    override func setUp() {
        super.setUp()
        client = FakeUserNotificationCenterClient()
        store = InMemoryNotifiedEventStore()
        preferences = FakeNotificationPreferenceStore()
        let permissions = NotificationPermissionCoordinator(client: client, preferences: preferences)
        dispatcher = NotificationDispatcher(client: client, store: store, permissions: permissions)
    }

    private func makeNotification(id: String = "tx.test-id",
                                  topic: NotificationTopic = .transactions,
                                  route: DeepLinkRoute? = .staking,
                                  behavior: NotificationForegroundBehavior = .banner) -> AppNotification {
        AppNotification(id: id,
                        topic: topic,
                        title: nil,
                        body: "body",
                        sound: nil,
                        route: route,
                        foregroundBehavior: behavior)
    }

    func testPostBuildsImmediateRequestWithTopicThreadAndCategory() async {
        await dispatcher.post(makeNotification())

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, "tx.test-id")
        // Immediate delivery: a delayed trigger races the foreground return.
        XCTAssertNil(request.trigger)
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.transactions.rawValue)
        XCTAssertEqual(request.content.categoryIdentifier, NotificationTopic.transactions.rawValue)
    }

    func testSecondPostWithSameIdIsDropped() async {
        await dispatcher.post(makeNotification(id: "tx.duplicate"))
        await dispatcher.post(makeNotification(id: "tx.duplicate"))

        XCTAssertEqual(client.addedRequests.count, 1)
    }

    func testPostDroppedWhenUserDisabledNotifications() async {
        preferences.userWantsNotifications = false

        await dispatcher.post(makeNotification())

        XCTAssertTrue(client.addedRequests.isEmpty)
        // Dropped before the dedup mark: the event stays postable once the
        // user re-enables notifications.
        XCTAssertTrue(store.events.isEmpty)
    }

    func testPostDroppedWhenSystemDenied() async {
        client.authorizationStatusValue = .denied

        await dispatcher.post(makeNotification())

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertTrue(store.events.isEmpty)
    }

    func testBadgeIsStoreUnseenCount() async {
        store.seed(id: "earlier.1", topic: .transactions)
        store.seed(id: "earlier.2", topic: .crowdnode)
        store.seed(id: "already.seen", topic: .transactions, seen: true)

        await dispatcher.post(makeNotification(id: "tx.third"))

        // Two unseen seeds plus the just-posted event; the seen one is out.
        XCTAssertEqual(client.addedRequests[0].content.badge, NSNumber(value: 3))
    }

    func testInterruptionLevelIsTimeSensitiveOnlyForTransactions() async {
        await dispatcher.post(makeNotification(id: "tx.a", topic: .transactions))
        await dispatcher.post(makeNotification(id: "cn.a", topic: .crowdnode))

        XCTAssertEqual(client.addedRequests[0].content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(client.addedRequests[1].content.interruptionLevel, .active)
    }

    func testRouteAndForegroundBehaviorRoundTripThroughUserInfo() async {
        await dispatcher.post(makeNotification(route: .staking, behavior: .suppress))

        let userInfo = client.addedRequests[0].content.userInfo
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: userInfo), .staking)
        XCTAssertEqual(userInfo[NotificationUserInfoKey.foregroundBehavior] as? String,
                       NotificationForegroundBehavior.suppress.rawValue)
    }

    func testRegisterCategoriesRegistersOnePerTopicWithInactivityActionsOnSystem() {
        dispatcher.registerCategories()

        XCTAssertEqual(client.registeredCategorySets.count, 1)
        let categories = client.registeredCategorySets[0]
        XCTAssertEqual(Set(categories.map(\.identifier)),
                       Set(NotificationTopic.allCases.map(\.rawValue)))
        // Only the system topic carries actions: the inactivity reminder's
        // remind-later and opt-out pair.
        let system = categories.first { $0.identifier == NotificationTopic.system.rawValue }
        XCTAssertEqual(system?.actions.map(\.identifier),
                       [InactivityReminderScheduler.remindLaterActionIdentifier,
                        InactivityReminderScheduler.optOutActionIdentifier])
        XCTAssertTrue(categories
            .filter { $0.identifier != NotificationTopic.system.rawValue }
            .allSatisfy { $0.actions.isEmpty })
    }
}
