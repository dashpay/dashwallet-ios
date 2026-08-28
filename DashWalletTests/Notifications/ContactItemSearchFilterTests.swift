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

#if DASHPAY

import XCTest
@testable import dashwallet

/// `ContactItem.matches(searchQuery:)` — the local-search predicate the
/// contacts and notifications screens both filter with.
final class ContactItemSearchFilterTests: XCTestCase {
    private static let anyDate = Date(timeIntervalSince1970: 1_756_000_000)

    func testCaseInsensitiveSubstringOnDisplayTitle() {
        let item = ContactItem.fixture(
            relationship: .established,
            username: nil,
            profileDisplayName: "Alice Johnson",
            createdAt: Self.anyDate)

        XCTAssertTrue(item.matches(searchQuery: "aLiCe"))
        XCTAssertTrue(item.matches(searchQuery: "JOHN"))
    }

    func testMatchesUsernameEvenWhenAnAliasRenders() {
        // The alias wins `displayTitle`, but searching by the DPNS handle
        // must still find the renamed contact.
        let item = ContactItem.fixture(
            relationship: .established,
            username: "bob.dash",
            alias: "My Brother",
            createdAt: Self.anyDate)

        XCTAssertTrue(item.matches(searchQuery: "BOB"))
        XCTAssertTrue(item.matches(searchQuery: "brother"))
    }

    func testEmptyAndWhitespaceQueriesMatchEverything() {
        let item = ContactItem.fixture(
            relationship: .incoming,
            username: "carol",
            createdAt: Self.anyDate)

        XCTAssertTrue(item.matches(searchQuery: ""))
        XCTAssertTrue(item.matches(searchQuery: "   "))
    }

    func testNoMatchReturnsFalse() {
        let item = ContactItem.fixture(
            relationship: .incoming,
            username: "carol",
            createdAt: Self.anyDate)

        XCTAssertFalse(item.matches(searchQuery: "dave"))
    }
}

#endif
