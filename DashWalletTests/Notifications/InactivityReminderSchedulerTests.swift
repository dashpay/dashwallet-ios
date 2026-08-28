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

/// Drives the scheduler directly (and once through the app-lifecycle
/// notification it observes). The real wall clock stays in place: a
/// calendar trigger built from a synthetic past date could never fire, so
/// the ~30-day assertion is made relative to `Date()`.
@MainActor
final class InactivityReminderSchedulerTests: XCTestCase {
    private final class FakeInactivityReminderPreferenceStore: InactivityReminderPreferenceStore {
        var isOptedOut = false
    }

    private var client: FakeUserNotificationCenterClient!
    private var notificationPreferences: FakeNotificationPreferenceStore!
    private var reminderPreferences: FakeInactivityReminderPreferenceStore!
    private var balance: UInt64 = 250_000
    private var scheduler: InactivityReminderScheduler!

    override func setUp() async throws {
        try await super.setUp()
        client = FakeUserNotificationCenterClient()
        notificationPreferences = FakeNotificationPreferenceStore()
        reminderPreferences = FakeInactivityReminderPreferenceStore()
        balance = 250_000
        let permissions = NotificationPermissionCoordinator(client: client,
                                                            preferences: notificationPreferences)
        scheduler = InactivityReminderScheduler(
            client: client,
            permissions: permissions,
            preferences: reminderPreferences,
            totalBalance: { [weak self] in self?.balance ?? 0 })
    }

    override func tearDown() async throws {
        // Drop the observers registered in start() before the next test's
        // instance exists.
        scheduler = nil
        try await super.tearDown()
    }

    // MARK: Scheduling

    func testSchedulesCalendarTriggerThirtyDaysOutWithBalanceInBody() async throws {
        await scheduler.scheduleReminder()

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = try XCTUnwrap(client.addedRequests.first)
        XCTAssertEqual(request.identifier, InactivityReminderScheduler.requestIdentifier)
        XCTAssertEqual(request.identifier, "system.inactivity")
        XCTAssertEqual(request.content.categoryIdentifier, NotificationTopic.system.rawValue)
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.system.rawValue)
        XCTAssertTrue(request.content.body.contains(UInt64(250_000).formattedDashAmount))
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo), .home)

        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        let fireDate = try XCTUnwrap(trigger.nextTriggerDate())
        let expected = Date().addingTimeInterval(InactivityReminderScheduler.reminderDelay)
        XCTAssertEqual(fireDate.timeIntervalSince(expected), 0, accuracy: 5 * 60)
    }

    func testZeroBalanceSchedulesNothing() async {
        balance = 0

        await scheduler.scheduleReminder()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testOptedOutSchedulesNothing() async {
        reminderPreferences.isOptedOut = true

        await scheduler.scheduleReminder()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testOffByUserSchedulesNothing() async {
        notificationPreferences.userWantsNotifications = false

        await scheduler.scheduleReminder()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testSystemDeniedSchedulesNothing() async {
        client.authorizationStatusValue = .denied

        await scheduler.scheduleReminder()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testReschedulingReplacesUnderTheSameIdentifier() async {
        await scheduler.scheduleReminder()
        await scheduler.scheduleReminder()

        // Same identifier both times — UNUserNotificationCenter replaces
        // the pending request, so only one reminder can ever be pending.
        XCTAssertEqual(client.addedRequests.count, 2)
        XCTAssertEqual(Set(client.addedRequests.map(\.identifier)), ["system.inactivity"])
    }

    // MARK: Cancellation

    func testCancelRemovesThePendingRequest() {
        scheduler.cancelPendingReminder()

        XCTAssertEqual(client.removedPendingIdentifiers, [["system.inactivity"]])
    }

    // MARK: Category actions

    func testOptOutActionPersistsAndCancels() {
        scheduler.handleOptOut()

        XCTAssertTrue(reminderPreferences.isOptedOut)
        XCTAssertEqual(client.removedPendingIdentifiers, [["system.inactivity"]])
    }

    func testRemindLaterActionReschedules() {
        let rescheduled = expectation(description: "request added")
        client.onAdd = { _ in rescheduled.fulfill() }

        scheduler.handleRemindLater()

        wait(for: [rescheduled], timeout: 2)
        XCTAssertEqual(client.addedRequests.first?.identifier, "system.inactivity")
    }

    // MARK: Lifecycle observation

    func testDidEnterBackgroundNotificationSchedules() {
        let scheduled = expectation(description: "request added")
        client.onAdd = { _ in scheduled.fulfill() }
        scheduler.start()

        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        wait(for: [scheduled], timeout: 2)
    }

    func testDidBecomeActiveNotificationCancels() {
        let cancelled = expectation(description: "pending removed")
        client.onRemovePendingIdentifiers = { identifiers in
            if identifiers == ["system.inactivity"] {
                cancelled.fulfill()
            }
        }
        scheduler.start()

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        wait(for: [cancelled], timeout: 2)
    }
}
