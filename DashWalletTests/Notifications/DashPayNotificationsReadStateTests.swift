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

/// Pure read-state arithmetic behind the bell: what counts as unread and
/// where viewing advances the marker to. Exercised directly — the contacts
/// service singleton only delegates here.
final class DashPayNotificationsReadStateTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func date(secondsAgo: TimeInterval) -> Date {
        Self.now.addingTimeInterval(-secondsAgo)
    }

    // MARK: Outgoing requests join the read-state

    func testOutgoingOnlyNewerEventCountsAndAdvancesMarker() {
        // The regression this guards: an outgoing request newer than every
        // incoming one used to badge the bell forever, because neither the
        // count nor the marker looked at the outgoing list.
        let lastViewed = date(secondsAgo: 600)
        let outgoing = ContactItem.fixture(relationship: .outgoing, createdAt: date(secondsAgo: 60))

        XCTAssertEqual(
            DashPayNotificationsReadState.unreadCount(
                incoming: [], outgoing: [outgoing], contacts: [], lastViewed: lastViewed),
            1)
        XCTAssertEqual(
            DashPayNotificationsReadState.advancedMarker(
                incoming: [], outgoing: [outgoing], contacts: [], lastViewed: lastViewed),
            outgoing.createdAt)
    }

    func testCountSpansAllThreeListsAndSkipsViewedEvents() {
        let lastViewed = date(secondsAgo: 600)
        let incoming = ContactItem.fixture(idByte: 0x01, relationship: .incoming, createdAt: date(secondsAgo: 30))
        let outgoing = ContactItem.fixture(idByte: 0x02, relationship: .outgoing, createdAt: date(secondsAgo: 60))
        let established = ContactItem.fixture(idByte: 0x03, relationship: .established, createdAt: date(secondsAgo: 90))
        let viewedEstablished = ContactItem.fixture(idByte: 0x04, relationship: .established, createdAt: date(secondsAgo: 900))

        XCTAssertEqual(
            DashPayNotificationsReadState.unreadCount(
                incoming: [incoming],
                outgoing: [outgoing],
                contacts: [established, viewedEstablished],
                lastViewed: lastViewed),
            3)
    }

    func testNilLastViewedCountsEverything() {
        let incoming = ContactItem.fixture(relationship: .incoming, createdAt: date(secondsAgo: 30))

        XCTAssertEqual(
            DashPayNotificationsReadState.unreadCount(
                incoming: [incoming], outgoing: [], contacts: [], lastViewed: nil),
            1)
        XCTAssertEqual(
            DashPayNotificationsReadState.advancedMarker(
                incoming: [incoming], outgoing: [], contacts: [], lastViewed: nil),
            incoming.createdAt)
    }

    func testEventExactlyAtTheMarkerIsRead() {
        // The marker is set to the newest displayed event's own date, so
        // "at the marker" means "already viewed" — strict comparison.
        let lastViewed = date(secondsAgo: 60)
        let item = ContactItem.fixture(relationship: .incoming, createdAt: lastViewed)

        XCTAssertEqual(
            DashPayNotificationsReadState.unreadCount(
                incoming: [item], outgoing: [], contacts: [], lastViewed: lastViewed),
            0)
        XCTAssertNil(
            DashPayNotificationsReadState.advancedMarker(
                incoming: [item], outgoing: [], contacts: [], lastViewed: lastViewed))
    }

    // MARK: Marker safety

    func testEmptyListsCountNothingAndAdvanceNothing() {
        XCTAssertEqual(
            DashPayNotificationsReadState.unreadCount(
                incoming: [], outgoing: [], contacts: [], lastViewed: nil),
            0)
        XCTAssertNil(
            DashPayNotificationsReadState.advancedMarker(
                incoming: [], outgoing: [], contacts: [], lastViewed: nil))
        XCTAssertNil(
            DashPayNotificationsReadState.advancedMarker(
                incoming: [], outgoing: [], contacts: [], lastViewed: date(secondsAgo: 60)))
    }

    func testMarkerNeverMovesBackward() {
        // Marker already past every event (the newest rows were removed
        // since the last viewing): no advance is offered.
        let lastViewed = date(secondsAgo: 10)
        let older = ContactItem.fixture(relationship: .incoming, createdAt: date(secondsAgo: 60))

        XCTAssertNil(
            DashPayNotificationsReadState.advancedMarker(
                incoming: [older], outgoing: [], contacts: [], lastViewed: lastViewed))
    }

    func testMarkerAdvancesToTheNewestAcrossAllLists() {
        let incoming = ContactItem.fixture(idByte: 0x01, relationship: .incoming, createdAt: date(secondsAgo: 90))
        let outgoing = ContactItem.fixture(idByte: 0x02, relationship: .outgoing, createdAt: date(secondsAgo: 30))
        let established = ContactItem.fixture(idByte: 0x03, relationship: .established, createdAt: date(secondsAgo: 60))

        XCTAssertEqual(
            DashPayNotificationsReadState.advancedMarker(
                incoming: [incoming], outgoing: [outgoing], contacts: [established], lastViewed: nil),
            outgoing.createdAt)
    }
}

#endif
