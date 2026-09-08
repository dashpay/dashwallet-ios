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

import UIKit
import XCTest
@testable import dashpay

/// Drives the hold through its two seams: a fake host records the
/// background-task begin/end pairs (and hands back the expiration handler
/// the system would call), and the wait is a continuation the test resumes
/// itself.
@MainActor
final class BackgroundGraceHoldTests: XCTestCase {
    /// Records what the hold asked of `UIApplication`, and keeps the
    /// expiration handler so a test can fire it like the system would.
    private final class FakeBackgroundTaskHost: BackgroundTaskHost {
        var nextIdentifier = UIBackgroundTaskIdentifier(rawValue: 7)
        var beginCount = 0
        var endedIdentifiers: [UIBackgroundTaskIdentifier] = []
        var expirationHandler: (() -> Void)?

        func beginBackgroundTask(withName name: String?,
                                 expirationHandler: (() -> Void)?) -> UIBackgroundTaskIdentifier {
            beginCount += 1
            self.expirationHandler = expirationHandler
            return nextIdentifier
        }

        func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
            endedIdentifiers.append(identifier)
        }
    }

    private var host: FakeBackgroundTaskHost!
    private var preferences: FakeNotificationPreferenceStore!
    private var permissions: NotificationPermissionCoordinator!
    /// Set only by the test that needs to observe the wait starting — an
    /// expectation created for every test would go unwaited.
    private var waitStarted: XCTestExpectation?
    private var resumeWait: (() -> Void)?
    private var hold: BackgroundGraceHold!

    override func setUp() async throws {
        try await super.setUp()
        host = FakeBackgroundTaskHost()
        preferences = FakeNotificationPreferenceStore()
        permissions = NotificationPermissionCoordinator(client: FakeUserNotificationCenterClient(),
                                                        preferences: preferences)
        hold = makeHold()
    }

    override func tearDown() async throws {
        // Release the suspended wait so no task outlives the test.
        resumeWait?()
        resumeWait = nil
        hold = nil
        try await super.tearDown()
    }

    private func makeHold() -> BackgroundGraceHold {
        BackgroundGraceHold(host: host, permissions: permissions) { [weak self] _ in
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    self?.resumeWait = { continuation.resume() }
                    self?.waitStarted?.fulfill()
                }
            }
        }
    }

    func testBackgroundingTakesBackgroundTimeAndForegroundingReleasesIt() async {
        hold.beginHold()

        XCTAssertEqual(host.beginCount, 1)
        XCTAssertTrue(hold.isHolding)

        hold.endHold(reason: "foregrounded")

        XCTAssertEqual(host.endedIdentifiers, [host.nextIdentifier])
        XCTAssertFalse(hold.isHolding)
    }

    /// The wait's own expiry is the normal end of the hold.
    func testHoldEndsWhenTheGracePeriodElapses() async {
        let started = expectation(description: "wait started")
        started.assertForOverFulfill = false
        waitStarted = started

        hold.beginHold()
        await fulfillment(of: [started], timeout: 1)

        resumeWait?()
        resumeWait = nil

        // Let the resumed task run to its `endHold`.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(host.endedIdentifiers, [host.nextIdentifier])
        XCTAssertFalse(hold.isHolding)
    }

    /// The system reclaiming its loan must end the task, not be ignored —
    /// overstaying is what gets a process killed.
    func testSystemExpirationHandlerReleasesTheTask() {
        hold.beginHold()

        host.expirationHandler?()

        XCTAssertEqual(host.endedIdentifiers, [host.nextIdentifier])
        XCTAssertFalse(hold.isHolding)
    }

    func testSecondBackgroundingWhileHoldingDoesNotTakeATaskTwice() {
        hold.beginHold()
        hold.beginHold()

        XCTAssertEqual(host.beginCount, 1)
    }

    func testReleasingWhenNothingIsHeldIsANoOp() {
        hold.endHold(reason: "foregrounded")

        XCTAssertTrue(host.endedIdentifiers.isEmpty)
    }

    /// A user who switched notifications off gets no background time spent
    /// on producing them.
    func testNoHoldWhenTheUserWantsNoNotifications() {
        preferences.userWantsNotifications = false

        hold.beginHold()

        XCTAssertEqual(host.beginCount, 0)
        XCTAssertFalse(hold.isHolding)
    }

    /// A refused loan (`.invalid`) must not leave the hold believing it
    /// owns one — the next backgrounding has to be free to ask again.
    func testRefusedBackgroundTimeLeavesNothingHeld() {
        host.nextIdentifier = .invalid

        hold.beginHold()

        XCTAssertFalse(hold.isHolding)
        XCTAssertTrue(host.endedIdentifiers.isEmpty)

        host.nextIdentifier = UIBackgroundTaskIdentifier(rawValue: 9)
        hold.beginHold()

        XCTAssertEqual(host.beginCount, 2)
        XCTAssertTrue(hold.isHolding)
    }
}
