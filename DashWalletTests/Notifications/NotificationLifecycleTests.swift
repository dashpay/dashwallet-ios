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
@testable import dashpay

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
    // `willPresent` cannot be invoked from a test. It forwards to
    // `completePresentation(userInfo:completionHandler:)`, exercised below
    // together with the `presentationOptions(forUserInfo:)` mapping.

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
        // Other threads keep their delivered notifications, but the zeroed
        // badge covered them too, so their store records are seen as well —
        // the next posted badge must not count them again.
        XCTAssertEqual(store.markAllSeenCalls, 1)
        XCTAssertEqual(store.events["CrowdNode"]?.seen, true)
        let unseen = await store.unseenCount()
        XCTAssertEqual(unseen, 0)
    }

    func testReconcileRemovesNothingWhenNoTransactionNotificationsDelivered() async {
        client.deliveredSummaries = [
            DeliveredNotificationSummary(identifier: "CrowdNode", threadIdentifier: NotificationTopic.crowdnode.rawValue),
        ]

        await lifecycle.reconcileAfterBecomingActive()

        XCTAssertEqual(client.badgeCounts, [0])
        XCTAssertTrue(client.removedDeliveredIdentifiers.isEmpty)
    }

    #if DASHPAY
    // MARK: DashPay notifications viewed (bell ↔ tray shared seen-state)

    func testDashPayViewedClearsDashPayThreadAndStoreTopicOnly() async {
        client.deliveredSummaries = [
            DeliveredNotificationSummary(identifier: "contact.request.aa",
                                         threadIdentifier: NotificationTopic.dashpay.rawValue),
            DeliveredNotificationSummary(identifier: "tx.1",
                                         threadIdentifier: NotificationTopic.transactions.rawValue),
        ]
        store.seed(id: "contact.request.aa", topic: .dashpay)
        store.seed(id: "tx.1", topic: .transactions)

        await lifecycle.reconcileAfterDashPayNotificationsViewed()

        XCTAssertEqual(client.removedDeliveredIdentifiers, [["contact.request.aa"]])
        XCTAssertEqual(store.markAllSeenTopics, [.dashpay])
        XCTAssertEqual(store.events["contact.request.aa"]?.seen, true)
        // Other topics keep their delivered notifications and unseen state.
        XCTAssertEqual(store.events["tx.1"]?.seen, false)
        // Bell-screen exit is not an activation: the badge is untouched.
        XCTAssertTrue(client.badgeCounts.isEmpty)
    }

    func testDashPayViewedRemovesNothingWhenTrayHasNoDashPayThread() async {
        client.deliveredSummaries = [
            DeliveredNotificationSummary(identifier: "tx.1",
                                         threadIdentifier: NotificationTopic.transactions.rawValue),
        ]

        await lifecycle.reconcileAfterDashPayNotificationsViewed()

        XCTAssertTrue(client.removedDeliveredIdentifiers.isEmpty)
        // The store seen-state still reconciles — dashpay events consumed
        // in-foreground never had a tray entry to remove.
        XCTAssertEqual(store.markAllSeenTopics, [.dashpay])
    }
    #endif

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
    // `didReceive` forwards to `completeResponse`, whose completion-handler
    // contract is tested in "Delegate completion" below.

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

    // MARK: Delegate completion
    //
    // A delegate method that returns without calling its completion handler
    // makes iOS drop the notification. These pin that every path acknowledges
    // exactly once, so a guard reintroduced around the call fails here.

    func testPresentationCompletesOnceForAPayloadWithoutBehavior() {
        var calls: [UNNotificationPresentationOptions] = []

        NotificationLifecycle.completePresentation(userInfo: [:]) { calls.append($0) }

        XCTAssertEqual(calls, [NotificationLifecycle.defaultPresentationOptions])
    }

    func testPresentationCompletesOnceWhenSuppressed() {
        var calls: [UNNotificationPresentationOptions] = []

        NotificationLifecycle.completePresentation(userInfo: userInfo(behavior: .suppress)) { calls.append($0) }

        XCTAssertEqual(calls, [[]])
    }

    func testResponseCompletesOnceForAnUnknownActionIdentifier() {
        var completions = 0

        lifecycle.completeResponse(actionIdentifier: "com.example.unknown-action",
                                   identifier: "announcement.1",
                                   userInfo: [:]) { completions += 1 }

        XCTAssertEqual(completions, 1)
        XCTAssertTrue(router.openedRoutes.isEmpty)
    }

    func testResponseCompletesOnceForATapWithoutRoute() {
        var completions = 0

        lifecycle.completeResponse(actionIdentifier: UNNotificationDefaultActionIdentifier,
                                   identifier: "tx.some-id",
                                   userInfo: [:]) { completions += 1 }

        XCTAssertEqual(completions, 1)
        XCTAssertTrue(router.openedRoutes.isEmpty)
    }

    func testResponseCompletesOnceAfterRoutingATap() {
        var completions = 0
        var routedBeforeCompletion = false
        var userInfo: [AnyHashable: Any] = [:]
        userInfo[NotificationUserInfoKey.route] = DeepLinkRoute.home.encodedForUserInfo()

        lifecycle.completeResponse(actionIdentifier: UNNotificationDefaultActionIdentifier,
                                   identifier: "announcement.1",
                                   userInfo: userInfo) {
            routedBeforeCompletion = self.router.openedRoutes == [.home]
            completions += 1
        }

        XCTAssertEqual(completions, 1)
        XCTAssertTrue(routedBeforeCompletion)
    }

    func testResponseCompletesOnceForAnInactivityAction() {
        let handler = RecordingInactivityHandler()
        lifecycle.inactivityReminderHandler = handler
        var completions = 0

        lifecycle.completeResponse(actionIdentifier: InactivityReminderScheduler.optOutActionIdentifier,
                                   identifier: InactivityReminderScheduler.requestIdentifier,
                                   userInfo: [:]) { completions += 1 }

        XCTAssertEqual(completions, 1)
        XCTAssertEqual(handler.optOutCount, 1)
    }
}
