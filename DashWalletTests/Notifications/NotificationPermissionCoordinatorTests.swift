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

final class NotificationPermissionCoordinatorTests: XCTestCase {
    private var client: FakeUserNotificationCenterClient!
    private var preferences: FakeNotificationPreferenceStore!
    private var coordinator: NotificationPermissionCoordinator!

    override func setUp() {
        super.setUp()
        client = FakeUserNotificationCenterClient()
        preferences = FakeNotificationPreferenceStore()
        coordinator = NotificationPermissionCoordinator(client: client, preferences: preferences)
    }

    private func derivedState(userWants: Bool,
                              status: UNAuthorizationStatus) async -> NotificationPermissionState {
        preferences.userWantsNotifications = userWants
        client.authorizationStatusValue = status
        return await coordinator.effectiveState()
    }

    func testDerivedStateMatrix() async {
        // The toggle is on and the OS does not forbid — .on. `.notDetermined`
        // counts as not-forbidden (the app simply hasn't asked yet).
        var state = await derivedState(userWants: true, status: .authorized)
        XCTAssertEqual(state, .on)
        state = await derivedState(userWants: true, status: .provisional)
        XCTAssertEqual(state, .on)
        state = await derivedState(userWants: true, status: .notDetermined)
        XCTAssertEqual(state, .on)

        // The toggle is off — .offByUser, whatever the (non-denied) OS grant.
        state = await derivedState(userWants: false, status: .authorized)
        XCTAssertEqual(state, .offByUser)
        state = await derivedState(userWants: false, status: .notDetermined)
        XCTAssertEqual(state, .offByUser)

        // OS denial wins over the toggle in both positions: the Settings row
        // must offer the way out (iOS Settings) either way.
        state = await derivedState(userWants: true, status: .denied)
        XCTAssertEqual(state, .blockedBySystem)
        state = await derivedState(userWants: false, status: .denied)
        XCTAssertEqual(state, .blockedBySystem)
    }

    func testDerivedStateNeverWritesTheToggle() async {
        preferences.userWantsNotifications = true
        client.authorizationStatusValue = .denied

        _ = await coordinator.effectiveState()

        // The OS grant must never be mirrored into the user preference.
        XCTAssertTrue(preferences.userWantsNotifications)
    }

    func testUserWantsNotificationsWritesPreferenceStore() {
        coordinator.userWantsNotifications = false
        XCTAssertFalse(preferences.userWantsNotifications)
        coordinator.userWantsNotifications = true
        XCTAssertTrue(preferences.userWantsNotifications)
    }

    @MainActor
    func testRequestAuthorizationPostsSignalsAndRequestsBadgeSoundAlert() async {
        let willRequest = expectation(description: "willRequestOSPermission posted")
        let didRequest = expectation(description: "didRequestOSPermission posted")
        let willObserver = NotificationCenter.default.addObserver(
            forName: .willRequestOSPermission, object: nil, queue: .main) { _ in
            willRequest.fulfill()
        }
        let didObserver = NotificationCenter.default.addObserver(
            forName: .didRequestOSPermission, object: nil, queue: .main) { _ in
            didRequest.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(willObserver)
            NotificationCenter.default.removeObserver(didObserver)
        }

        coordinator.requestAuthorizationIfNeeded()

        await fulfillment(of: [willRequest, didRequest], timeout: 2)
        XCTAssertEqual(client.requestedAuthorizationOptions, [[.badge, .sound, .alert]])
    }
}
