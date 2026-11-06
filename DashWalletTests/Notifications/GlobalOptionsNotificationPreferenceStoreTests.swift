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
@testable import dashpay

/// Guards the production toggle storage against the failure it actually had:
/// `DWGlobalOptions.localNotificationsEnabled` was declared but never listed
/// `@dynamic`, so the compiler synthesized an ivar-backed accessor, the
/// `DSDynamicOptions` runtime accessor never got installed, and the property
/// stopped being a user default — reading `false` on every launch (the whole
/// feature gated off) and forgetting the user's choice at termination.
/// Both assertions below fail if that regresses.
final class GlobalOptionsNotificationPreferenceStoreTests: XCTestCase {
    /// The key `DWGlobalOptions.defaultsKeyForPropertyName` maps the
    /// property to.
    private static let defaultsKey = "USER_DEFAULTS_LOCAL_NOTIFICATIONS_KEY"

    private var store: GlobalOptionsNotificationPreferenceStore!
    private var original: Any?

    override func setUp() {
        super.setUp()
        store = GlobalOptionsNotificationPreferenceStore()
        original = UserDefaults.standard.object(forKey: Self.defaultsKey)
    }

    override func tearDown() {
        if let original {
            UserDefaults.standard.set(original, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
        store = nil
        super.tearDown()
    }

    /// Writes must land in user defaults, not in an ivar that dies with the
    /// process.
    func testTogglePersistsThroughUserDefaults() {
        store.userWantsNotifications = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool, false)
        XCTAssertFalse(store.userWantsNotifications)

        store.userWantsNotifications = true
        XCTAssertEqual(UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool, true)
        XCTAssertTrue(store.userWantsNotifications)
    }

    /// An install that never touched the toggle wants notifications — the
    /// registered default is `@YES`, and reading `false` there switches the
    /// entire feature off silently.
    func testUntouchedInstallWantsNotifications() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)

        XCTAssertTrue(store.userWantsNotifications)
    }
}
