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
import UserNotifications
@testable import dashpay

/// Feeds synthetic contact snapshots through `scanAndNotify` against the
/// real dispatcher over the in-memory store, so the
/// store-dedup-as-new-vs-known-detector design is exercised for real.
@MainActor
final class DashPayContactsNotificationProducerTests: XCTestCase {
    /// Fixed wall clock handed to the producer; items are stamped relative
    /// to it.
    private static let referenceNow = Date(timeIntervalSince1970: 1_756_000_000)

    /// Two receiving identities sharing one app-wide `NotifiedEventStore`.
    static let ownerA = Data(repeating: 0x01, count: 32)
    static let ownerB = Data(repeating: 0x02, count: 32)
    static let ownerAHex = ownerA.hexEncodedString()
    static let ownerBHex = ownerB.hexEncodedString()

    private var client: FakeUserNotificationCenterClient!
    private var store: InMemoryNotifiedEventStore!
    private var preferences: FakeNotificationPreferenceStore!
    private var dispatcher: NotificationDispatcher!
    private var appState: FakeAppStateProvider!
    private var snapshot = DashPayContactsNotificationProducer.ContactsSnapshot(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [], contacts: [])
    private var producer: DashPayContactsNotificationProducer!

    override func setUp() async throws {
        try await super.setUp()
        client = FakeUserNotificationCenterClient()
        store = InMemoryNotifiedEventStore()
        preferences = FakeNotificationPreferenceStore()
        appState = FakeAppStateProvider()
        snapshot = DashPayContactsNotificationProducer.ContactsSnapshot(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [], contacts: [])
        let permissions = NotificationPermissionCoordinator(client: client, preferences: preferences)
        dispatcher = NotificationDispatcher(client: client, store: store, permissions: permissions)
        producer = DashPayContactsNotificationProducer(
            dispatcher: dispatcher,
            store: store,
            snapshot: { [weak self] in
                self?.snapshot ?? DashPayContactsNotificationProducer.ContactsSnapshot(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [], contacts: [])
            },
            appState: appState,
            now: { Self.referenceNow })
    }

    /// Ages-relative-to-`referenceNow` wrapper over the shared
    /// `ContactItem.fixture` (NotificationTestDoubles.swift).
    private func makeItem(idByte: UInt8 = 0xaa,
                          relationship: ContactRelationship,
                          username: String? = "alice",
                          age: TimeInterval = 60,
                          incomingAge: TimeInterval? = nil,
                          outgoingAge: TimeInterval? = nil) -> ContactItem {
        ContactItem.fixture(
            idByte: idByte,
            relationship: relationship,
            username: username,
            createdAt: Self.referenceNow.addingTimeInterval(-age),
            incomingCreatedAt: incomingAge.map { Self.referenceNow.addingTimeInterval(-$0) },
            outgoingCreatedAt: outgoingAge.map { Self.referenceNow.addingTimeInterval(-$0) })
    }

    private func idHex(_ byte: UInt8) -> String {
        String(repeating: String(format: "%02x", byte), count: 32)
    }

    /// The producer's id for an event: owner + counterparty + the event's own
    /// moment, which is what keeps two events for the same pair apart.
    private func eventId(_ kind: String, owner: String, item: ContactItem) -> String {
        let millis = Int64((item.createdAt.timeIntervalSince1970 * 1000).rounded())
        return "contact.\(kind).\(owner).\(item.contactIdentityId.hexEncodedString()).\(millis)"
    }

    // MARK: Incoming requests

    func testFreshIncomingRequestPostsOnceAcrossTwoChangeSignals() async {
        let item = makeItem(relationship: .incoming, incomingAge: 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [item], contacts: [])

        await producer.scanAndNotify()
        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, eventId("request", owner: DashPayContactsNotificationProducerTests.ownerAHex, item: item))
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.dashpay.rawValue)
        XCTAssertEqual(request.content.body,
                       String(format: NSLocalizedString("%@ has sent you a contact request", comment: "DashPay Notifications"), "alice"))
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo), .dashPayNotifications)
        XCTAssertEqual(request.content.userInfo[NotificationUserInfoKey.foregroundBehavior] as? String,
                       NotificationForegroundBehavior.suppress.rawValue)
    }

    func testTheSameCounterpartyNotifiesEachOwnerSeparately() async {
        // One app-wide store, two receiving identities. Keyed on the
        // counterparty alone, owner B's fresh request reused owner A's id
        // and was dropped as a duplicate.
        let item = makeItem(relationship: .incoming, incomingAge: 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA,
                         incomingRequests: [item], contacts: [])
        await producer.scanAndNotify()

        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerB,
                         incomingRequests: [item], contacts: [])
        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 2)
        XCTAssertEqual(client.addedRequests.map(\.identifier), [
            eventId("request", owner: DashPayContactsNotificationProducerTests.ownerAHex, item: item),
            eventId("request", owner: DashPayContactsNotificationProducerTests.ownerBHex, item: item),
        ])
    }

    func testHistoricalRequestDoesNotPost() async {
        // A freshly synced identity replays its request history — an item
        // outside the freshness window is not news.
        let item = makeItem(relationship: .incoming, age: 11 * 60, incomingAge: 11 * 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [item], contacts: [])

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    // MARK: Catch-up boundary

    func testCatchUpBoundaryPostsARequestReceivedWhileBackgrounded() async {
        // The background refresh runs at least 15 minutes after the app was
        // suspended; a request sent 20 minutes ago is past the default window.
        let item = makeItem(relationship: .incoming, age: 20 * 60, incomingAge: 20 * 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [item], contacts: [])

        await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-30 * 60))

        XCTAssertEqual(client.addedRequests.map(\.identifier),
                       [eventId("request", owner: DashPayContactsNotificationProducerTests.ownerAHex, item: item)])
    }

    func testWithoutABoundaryARequestPastTheWindowDoesNotPost() async {
        let item = makeItem(relationship: .incoming, age: 20 * 60, incomingAge: 20 * 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [item], contacts: [])

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testCatchUpBoundaryIsFlooredAtTheMaximumWindow() async {
        // A boundary from weeks ago is clamped: a dormant install must not
        // announce its whole request backlog.
        let item = makeItem(relationship: .incoming, age: 25 * 60 * 60, incomingAge: 25 * 60 * 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [item], contacts: [])

        await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-14 * 24 * 60 * 60))

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testCatchUpScanDoesNotRepostAnAlreadyPostedRequest() async {
        let item = makeItem(relationship: .incoming, age: 20 * 60, incomingAge: 20 * 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [item], contacts: [])
        let boundary = Self.referenceNow.addingTimeInterval(-30 * 60)

        await producer.scanAndNotify(since: boundary)
        await producer.scanAndNotify(since: boundary)

        XCTAssertEqual(client.addedRequests.count, 1)
    }

    func testRequestDatedBehindAnEarlierViewingStillPosts() async {
        // The bell marker once gated this producer. Viewing the screen moves
        // it to the newest event shown — here, our own outgoing request sent
        // a minute ago — and an incoming request stamped by the sender's
        // clock 30 s earlier, which arrived only after that viewing, was
        // dropped for good. The producer no longer reads the marker at all.
        let lateIncoming = makeItem(idByte: 0x22, relationship: .incoming, age: 90, incomingAge: 90)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA,
                         incomingRequests: [lateIncoming], contacts: [])

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.map(\.identifier),
                       [eventId("request", owner: DashPayContactsNotificationProducerTests.ownerAHex, item: lateIncoming)])
    }

    // MARK: Established contacts

    func testTheirAcceptOfOurRequestPosts() async {
        // Incoming row newer than outgoing: they reciprocated.
        let item = makeItem(idByte: 0xbb, relationship: .established,
                            username: "bob", age: 60,
                            incomingAge: 60, outgoingAge: 3_600)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [], contacts: [item])

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, eventId("accepted", owner: DashPayContactsNotificationProducerTests.ownerAHex, item: item))
        XCTAssertEqual(request.content.body,
                       String(format: NSLocalizedString("%@ accepted your contact request", comment: "DashPay Notifications"), "bob"))
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo), .dashPayNotifications)
    }

    func testOurOwnAcceptDoesNotPost() async {
        // Outgoing row newer than incoming: WE accepted — the user did it
        // themselves, nothing to announce.
        let item = makeItem(idByte: 0xcc, relationship: .established,
                            age: 60, incomingAge: 3_600, outgoingAge: 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [], contacts: [item])

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testUnknownAcceptOrderDoesNotPost() async {
        // Neither direction's timestamp is known, so nothing says THEY
        // accepted — a missing date is not the distant past.
        let item = makeItem(idByte: 0xdd, relationship: .established, age: 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [], contacts: [item])

        await producer.scanAndNotify()

        XCTAssertNil(item.establishedByTheirAccept)
        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    /// Equal direction timestamps name no accepting side. The two are derived
    /// independently from the direction rows, and `ContactProfileSheet` reads
    /// equality the other way round — so the order is unknown and nothing is
    /// announced.
    func testEqualDirectionTimestampsAreUnknownOrderAndDoNotPost() async {
        let item = makeItem(idByte: 0xce, relationship: .established,
                            age: 60, incomingAge: 60, outgoingAge: 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [], contacts: [item])

        await producer.scanAndNotify()

        XCTAssertNil(item.establishedByTheirAccept)
        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    /// The id carries the event's own moment, so a second request from the
    /// same counterparty is a second event — not the first one repeating.
    func testASecondRequestFromTheSameCounterpartyPostsAgain() async {
        let first = makeItem(relationship: .incoming, age: 300, incomingAge: 300)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [first], contacts: [])
        await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-30 * 60))

        let second = makeItem(relationship: .incoming, age: 60, incomingAge: 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [second], contacts: [])
        await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-30 * 60))

        XCTAssertEqual(client.addedRequests.map(\.identifier), [
            eventId("request", owner: DashPayContactsNotificationProducerTests.ownerAHex, item: first),
            eventId("request", owner: DashPayContactsNotificationProducerTests.ownerAHex, item: second),
        ])
    }

    func testOneMissingDirectionTimestampIsUnknownOrder() {
        let incomingOnly = makeItem(relationship: .established, incomingAge: 60)
        let outgoingOnly = makeItem(relationship: .established, outgoingAge: 60)
        let theirs = makeItem(relationship: .established, incomingAge: 60, outgoingAge: 120)
        let ours = makeItem(relationship: .established, incomingAge: 120, outgoingAge: 60)

        XCTAssertNil(incomingOnly.establishedByTheirAccept)
        XCTAssertNil(outgoingOnly.establishedByTheirAccept)
        XCTAssertEqual(theirs.establishedByTheirAccept, true)
        XCTAssertEqual(ours.establishedByTheirAccept, false)
    }

    // MARK: App-state policy

    func testForegroundSuppressPathConsumes() async {
        appState.isApplicationActive = true
        let item = makeItem(relationship: .incoming, incomingAge: 60)
        snapshot = .init(ownerIdentityId: DashPayContactsNotificationProducerTests.ownerA, incomingRequests: [item], contacts: [])

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        // Consumed: the bell showed it live, so a scan after backgrounding
        // cannot post it and the badge never counts it.
        XCTAssertEqual(store.events[eventId("request", owner: DashPayContactsNotificationProducerTests.ownerAHex, item: item)]?.seen, true)

        appState.isApplicationActive = false
        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }
}

#endif
