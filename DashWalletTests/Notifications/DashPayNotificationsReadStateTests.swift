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
@testable import dashpay

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
                incoming: [], outgoing: [outgoing], contacts: [], lastViewed: lastViewed, viewedKeys: nil),
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
                lastViewed: lastViewed, viewedKeys: nil),
            3)
    }

    func testNilLastViewedCountsEverything() {
        let incoming = ContactItem.fixture(relationship: .incoming, createdAt: date(secondsAgo: 30))

        XCTAssertEqual(
            DashPayNotificationsReadState.unreadCount(
                incoming: [incoming], outgoing: [], contacts: [], lastViewed: nil, viewedKeys: nil),
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
                incoming: [item], outgoing: [], contacts: [], lastViewed: lastViewed, viewedKeys: nil),
            0)
        XCTAssertNil(
            DashPayNotificationsReadState.advancedMarker(
                incoming: [item], outgoing: [], contacts: [], lastViewed: lastViewed))
    }

    // MARK: Viewed event keys

    func testRequestDatedBehindTheViewingStillCountsUnread() {
        // The finding this guards: the user viewed the screen while their
        // own outgoing request (60 s ago) was the newest event, which moved
        // the date marker there. An incoming request arriving afterwards,
        // stamped by the sender's clock 90 s ago, sat behind that marker and
        // was never counted. With recorded keys it is unread until shown.
        let ownOutgoing = ContactItem.fixture(idByte: 0x01, relationship: .outgoing, createdAt: date(secondsAgo: 60))
        let viewed = DashPayNotificationsReadState.recordingViewed(
            incoming: [], outgoing: [ownOutgoing], contacts: [], previous: nil)
        let marker = DashPayNotificationsReadState.advancedMarker(
            incoming: [], outgoing: [ownOutgoing], contacts: [], lastViewed: nil)
        let lateIncoming = ContactItem.fixture(idByte: 0x02, relationship: .incoming, createdAt: date(secondsAgo: 90))

        XCTAssertEqual(
            DashPayNotificationsReadState.unreadCount(
                incoming: [lateIncoming], outgoing: [ownOutgoing], contacts: [],
                lastViewed: marker, viewedKeys: viewed),
            1)
        XCTAssertTrue(DashPayNotificationsReadState.isUnread(lateIncoming, lastViewed: marker, viewedKeys: viewed))
        XCTAssertFalse(DashPayNotificationsReadState.isUnread(ownOutgoing, lastViewed: marker, viewedKeys: viewed))
    }

    func testViewingRecordsShownEventsAndKeepsEarlierOnes() {
        let first = ContactItem.fixture(idByte: 0x01, relationship: .incoming, createdAt: date(secondsAgo: 60))
        let second = ContactItem.fixture(idByte: 0x02, relationship: .established, createdAt: date(secondsAgo: 30))

        let afterFirst = DashPayNotificationsReadState.recordingViewed(
            incoming: [first], outgoing: [], contacts: [], previous: nil)
        // A viewing while the lists are briefly empty (snapshot mid-rebuild)
        // must not wipe what was recorded.
        let afterEmpty = DashPayNotificationsReadState.recordingViewed(
            incoming: [], outgoing: [], contacts: [], previous: afterFirst)
        let afterSecond = DashPayNotificationsReadState.recordingViewed(
            incoming: [], outgoing: [], contacts: [second], previous: afterEmpty)

        XCTAssertEqual(afterEmpty, afterFirst)
        XCTAssertEqual(afterSecond, [
            DashPayNotificationsReadState.eventKey(for: first),
            DashPayNotificationsReadState.eventKey(for: second),
        ])
    }

    func testResentRequestIsANewEvent() {
        // Same counterparty, same list, later timestamp: a new request.
        let original = ContactItem.fixture(idByte: 0x01, relationship: .incoming, createdAt: date(secondsAgo: 600))
        let resent = ContactItem.fixture(idByte: 0x01, relationship: .incoming, createdAt: date(secondsAgo: 30))
        let viewed = DashPayNotificationsReadState.recordingViewed(
            incoming: [original], outgoing: [], contacts: [], previous: nil)

        XCTAssertTrue(DashPayNotificationsReadState.isUnread(resent, lastViewed: nil, viewedKeys: viewed))
    }

    func testRecordedSetIsPrunedToShownEventsPastItsBound() {
        let stale = Set((0..<DashPayNotificationsReadState.viewedKeysLimit).map { "incoming.stale.\($0)" })
        let shown = ContactItem.fixture(relationship: .incoming, createdAt: date(secondsAgo: 30))

        let recorded = DashPayNotificationsReadState.recordingViewed(
            incoming: [shown], outgoing: [], contacts: [], previous: stale)

        XCTAssertEqual(recorded, [DashPayNotificationsReadState.eventKey(for: shown)])
    }

    // MARK: What a viewing stores

    /// `nil` stored keys are what keeps `isUnread` on the legacy date marker.
    /// A viewing that rendered nothing — the screen opened before contacts
    /// loaded — must leave that alone rather than write an empty set, which
    /// would switch the reader onto the key set and re-badge all history.
    func testAViewingWithNothingRenderedStoresNothing() {
        let recorded = DashPayNotificationsReadState.recordingViewed(
            incoming: [], outgoing: [], contacts: [], previous: nil)

        XCTAssertTrue(recorded.isEmpty)
        XCTAssertNil(DashPayNotificationsReadState.storedValue(forRecorded: recorded, previous: nil))
    }

    func testAnUnchangedSetStoresNothing() {
        let item = ContactItem.fixture(idByte: 0x01, relationship: .incoming, createdAt: date(secondsAgo: 60))
        let recorded = DashPayNotificationsReadState.recordingViewed(
            incoming: [item], outgoing: [], contacts: [], previous: nil)

        XCTAssertNotNil(DashPayNotificationsReadState.storedValue(forRecorded: recorded, previous: nil))
        XCTAssertNil(DashPayNotificationsReadState.storedValue(forRecorded: recorded, previous: recorded))
    }

    /// An empty set never overwrites keys already recorded either — that is
    /// the prune branch with nothing rendered.
    func testAnEmptySetNeverOverwritesRecordedKeys() {
        let previous: Set<String> = ["established.aa.1"]

        XCTAssertNil(DashPayNotificationsReadState.storedValue(forRecorded: [], previous: previous))
    }

    // MARK: Marker safety

    func testEmptyListsCountNothingAndAdvanceNothing() {
        XCTAssertEqual(
            DashPayNotificationsReadState.unreadCount(
                incoming: [], outgoing: [], contacts: [], lastViewed: nil, viewedKeys: nil),
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
