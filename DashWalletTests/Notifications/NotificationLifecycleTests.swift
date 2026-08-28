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
import UIKit
import UserNotifications
@testable import dashwallet

@MainActor
final class NotificationLifecycleTests: XCTestCase {
    private var client: FakeUserNotificationCenterClient!
    private var store: InMemoryNotifiedEventStore!
    private var router: RecordingNotificationRouter!
    private var lifecycle: NotificationLifecycle!

    override func setUp() async throws {
        try await super.setUp()
        client = FakeUserNotificationCenterClient()
        store = InMemoryNotifiedEventStore()
        router = RecordingNotificationRouter()
        lifecycle = NotificationLifecycle(client: client, store: store, router: router)
    }

    override func tearDown() async throws {
        // Drop the observer registered in init before the next test's
        // instance exists.
        lifecycle = nil
        try await super.tearDown()
    }

    private func userInfo(behavior: NotificationForegroundBehavior) -> [AnyHashable: Any] {
        [NotificationUserInfoKey.foregroundBehavior: behavior.rawValue]
    }

    // MARK: Foreground presentation
    //
    // `UNNotification` has no public initializer, so the delegate's
    // `willPresent` cannot be invoked from a test. It is a one-expression
    // trampoline over `presentationOptions(forUserInfo:)` that passes the
    // result straight to its completion handler — the mapping below is the
    // entire behavior.

    func testWillPresentOptionsSuppress() {
        XCTAssertEqual(NotificationLifecycle.presentationOptions(forUserInfo: userInfo(behavior: .suppress)), [])
    }

    func testWillPresentOptionsBanner() {
        XCTAssertEqual(NotificationLifecycle.presentationOptions(forUserInfo: userInfo(behavior: .banner)),
                       [.list, .banner, .sound])
    }

    func testWillPresentOptionsListOnly() {
        XCTAssertEqual(NotificationLifecycle.presentationOptions(forUserInfo: userInfo(behavior: .listOnly)),
                       [.list])
    }

    func testWillPresentOptionsDefaultForLegacyNotifications() {
        // No behavior key (pre-module delivery) and an unknown value both
        // fall back to the previous AppDelegate behavior.
        XCTAssertEqual(NotificationLifecycle.presentationOptions(forUserInfo: [:]),
                       [.list, .banner, .sound])
        let garbage: [AnyHashable: Any] = [NotificationUserInfoKey.foregroundBehavior: "not-a-behavior"]
        XCTAssertEqual(NotificationLifecycle.presentationOptions(forUserInfo: garbage),
                       [.list, .banner, .sound])
    }

    // MARK: Become-active reconciliation

    func testReconcileClearsBadgeTransactionsThreadAndLegacyNow() async {
        client.deliveredSummaries = [
            DeliveredNotificationSummary(identifier: "tx.1", threadIdentifier: NotificationTopic.transactions.rawValue),
            DeliveredNotificationSummary(identifier: "Now", threadIdentifier: ""),
            DeliveredNotificationSummary(identifier: "CrowdNode", threadIdentifier: NotificationTopic.crowdnode.rawValue),
        ]
        store.seed(id: "tx.1", topic: .transactions)
        store.seed(id: "CrowdNode", topic: .crowdnode)

        await lifecycle.reconcileAfterBecomingActive()

        XCTAssertEqual(client.badgeCounts, [0])
        XCTAssertEqual(client.removedDeliveredIdentifiers, [["tx.1", "Now"]])
        XCTAssertEqual(store.markAllSeenTopics, [.transactions])
        XCTAssertEqual(store.events["tx.1"]?.seen, true)
        // Other threads keep their delivered notifications and unseen state.
        XCTAssertEqual(store.events["CrowdNode"]?.seen, false)
    }

    func testReconcileRemovesNothingWhenNoTransactionNotificationsDelivered() async {
        client.deliveredSummaries = [
            DeliveredNotificationSummary(identifier: "CrowdNode", threadIdentifier: NotificationTopic.crowdnode.rawValue),
        ]

        await lifecycle.reconcileAfterBecomingActive()

        XCTAssertEqual(client.badgeCounts, [0])
        XCTAssertTrue(client.removedDeliveredIdentifiers.isEmpty)
    }

    func testDidBecomeActiveNotificationTriggersReconcile() async {
        let badgeCleared = expectation(description: "badge set to 0")
        client.onSetBadgeCount = { count in
            if count == 0 {
                badgeCleared.fulfill()
            }
        }

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        await fulfillment(of: [badgeCleared], timeout: 2)
    }

    // MARK: Tap routing
    //
    // `UNNotificationResponse` cannot be constructed either; the delegate's
    // `didReceive` trampolines into `handleNotificationTap` and calls its
    // completion handler unconditionally.

    func testTapWithEncodedRouteHandsItToRouter() {
        var userInfo = userInfo(behavior: .banner)
        userInfo[NotificationUserInfoKey.route] = DeepLinkRoute.url(URL(string: "https://www.dash.org")!).encodedForUserInfo()

        lifecycle.handleNotificationTap(identifier: "announcement.1", userInfo: userInfo)

        XCTAssertEqual(router.openedRoutes, [.url(URL(string: "https://www.dash.org")!)])
    }

    func testTapOnLegacyCrowdNodeIdentifierFoldsToStaking() {
        // Delivered by an older build: the CrowdNode identifier without an
        // encoded route must keep opening the CrowdNode screen.
        lifecycle.handleNotificationTap(identifier: CrowdNode.notificationID, userInfo: [:])

        XCTAssertEqual(router.openedRoutes, [.staking])
    }

    func testTapWithoutRouteDoesNothing() {
        lifecycle.handleNotificationTap(identifier: "tx.some-id", userInfo: [:])

        XCTAssertTrue(router.openedRoutes.isEmpty)
    }

    // MARK: Action dispatch

    private final class RecordingInactivityHandler: InactivityReminderActionHandling {
        private(set) var remindLaterCount = 0
        private(set) var optOutCount = 0

        func handleRemindLater() { remindLaterCount += 1 }
        func handleOptOut() { optOutCount += 1 }
    }

    func testInactivityActionIdentifiersDispatchToTheHandlerNotTheRouter() {
        let handler = RecordingInactivityHandler()
        lifecycle.inactivityReminderHandler = handler
        var userInfo: [AnyHashable: Any] = [:]
        userInfo[NotificationUserInfoKey.route] = DeepLinkRoute.home.encodedForUserInfo()

        lifecycle.handleNotificationResponse(
            actionIdentifier: InactivityReminderScheduler.remindLaterActionIdentifier,
            identifier: InactivityReminderScheduler.requestIdentifier,
            userInfo: userInfo)
        lifecycle.handleNotificationResponse(
            actionIdentifier: InactivityReminderScheduler.optOutActionIdentifier,
            identifier: InactivityReminderScheduler.requestIdentifier,
            userInfo: userInfo)

        XCTAssertEqual(handler.remindLaterCount, 1)
        XCTAssertEqual(handler.optOutCount, 1)
        XCTAssertTrue(router.openedRoutes.isEmpty)
    }

    func testDefaultActionFallsThroughToTapRouting() {
        let handler = RecordingInactivityHandler()
        lifecycle.inactivityReminderHandler = handler
        var userInfo: [AnyHashable: Any] = [:]
        userInfo[NotificationUserInfoKey.route] = DeepLinkRoute.url(URL(string: "https://www.dash.org")!).encodedForUserInfo()

        lifecycle.handleNotificationResponse(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            identifier: "announcement.1",
            userInfo: userInfo)

        XCTAssertEqual(router.openedRoutes, [.url(URL(string: "https://www.dash.org")!)])
        XCTAssertEqual(handler.remindLaterCount, 0)
        XCTAssertEqual(handler.optOutCount, 0)
    }
}
