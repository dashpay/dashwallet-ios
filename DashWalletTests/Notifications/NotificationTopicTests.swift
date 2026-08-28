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
@testable import dashwallet

final class NotificationTopicTests: XCTestCase {
    /// Raw values are wire/thread identifiers — renaming a case silently
    /// orphans delivered notifications, so the mapping is pinned here.
    func testRawValuesArePinned() {
        XCTAssertEqual(NotificationTopic.transactions.rawValue, "transactions")
        XCTAssertEqual(NotificationTopic.dashpay.rawValue, "dashpay")
        XCTAssertEqual(NotificationTopic.crowdnode.rawValue, "crowdnode")
        XCTAssertEqual(NotificationTopic.swap.rawValue, "swap")
        XCTAssertEqual(NotificationTopic.announcements.rawValue, "announcements")
        XCTAssertEqual(NotificationTopic.system.rawValue, "system")
    }
}
