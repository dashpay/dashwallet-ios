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
@testable import dashwallet

/// Feeds synthetic contact snapshots through `scanAndNotify` against the
/// real dispatcher over the in-memory store, so the
/// store-dedup-as-new-vs-known-detector design is exercised for real.
@MainActor
final class DashPayContactsNotificationProducerTests: XCTestCase {
    /// Fixed wall clock handed to the producer; items are stamped relative
    /// to it.
    private static let referenceNow = Date(timeIntervalSince1970: 1_756_000_000)

    private var client: FakeUserNotificationCenterClient!
    private var store: InMemoryNotifiedEventStore!
    private var preferences: FakeNotificationPreferenceStore!
    private var dispatcher: NotificationDispatcher!
    private var appState: FakeAppStateProvider!
    private var snapshot = DashPayContactsNotificationProducer.ContactsSnapshot(incomingRequests: [], contacts: [])
    private var lastViewed: Date?
    private var producer: DashPayContactsNotificationProducer!

    override func setUp() async throws {
        try await super.setUp()
        client = FakeUserNotificationCenterClient()
        store = InMemoryNotifiedEventStore()
        preferences = FakeNotificationPreferenceStore()
        appState = FakeAppStateProvider()
        snapshot = DashPayContactsNotificationProducer.ContactsSnapshot(incomingRequests: [], contacts: [])
        lastViewed = nil
        let permissions = NotificationPermissionCoordinator(client: client, preferences: preferences)
        dispatcher = NotificationDispatcher(client: client, store: store, permissions: permissions)
        producer = DashPayContactsNotificationProducer(
            dispatcher: dispatcher,
            store: store,
            snapshot: { [weak self] in
                self?.snapshot ?? DashPayContactsNotificationProducer.ContactsSnapshot(incomingRequests: [], contacts: [])
            },
            lastViewedDate: { [weak self] in self?.lastViewed },
            appState: appState,
            now: { Self.referenceNow })
    }

    private func makeItem(idByte: UInt8 = 0xaa,
                          relationship: ContactRelationship,
                          username: String? = "alice",
                          age: TimeInterval = 60,
                          incomingAge: TimeInterval? = nil,
                          outgoingAge: TimeInterval? = nil) -> ContactItem {
        ContactItem(
            contactIdentityId: Data(repeating: idByte, count: 32),
            relationship: relationship,
            username: username,
            profileDisplayName: nil,
            alias: nil,
            note: nil,
            isHidden: false,
            paymentChannelBroken: false,
            avatarURL: nil,
            publicMessage: nil,
            createdAt: Self.referenceNow.addingTimeInterval(-age),
            incomingCreatedAt: incomingAge.map { Self.referenceNow.addingTimeInterval(-$0) },
            outgoingCreatedAt: outgoingAge.map { Self.referenceNow.addingTimeInterval(-$0) })
    }

    private func idHex(_ byte: UInt8) -> String {
        String(repeating: String(format: "%02x", byte), count: 32)
    }

    // MARK: Incoming requests

    func testFreshIncomingRequestPostsOnceAcrossTwoChangeSignals() async {
        let item = makeItem(relationship: .incoming, incomingAge: 60)
        snapshot = .init(incomingRequests: [item], contacts: [])

        await producer.scanAndNotify()
        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, "contact.request.\(idHex(0xaa))")
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.dashpay.rawValue)
        XCTAssertEqual(request.content.body,
                       String(format: NSLocalizedString("%@ has sent you a contact request", comment: "DashPay Notifications"), "alice"))
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo), .dashPayNotifications)
        XCTAssertEqual(request.content.userInfo[NotificationUserInfoKey.foregroundBehavior] as? String,
                       NotificationForegroundBehavior.suppress.rawValue)
    }

    func testHistoricalRequestDoesNotPost() async {
        // A freshly synced identity replays its request history — an item
        // outside the freshness window is not news.
        let item = makeItem(relationship: .incoming, age: 11 * 60, incomingAge: 11 * 60)
        snapshot = .init(incomingRequests: [item], contacts: [])

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testAlreadyViewedRequestDoesNotPost() async {
        // The user opened the notifications screen after this request
        // arrived — the bell's read marker makes it old news.
        let item = makeItem(relationship: .incoming, age: 120, incomingAge: 120)
        snapshot = .init(incomingRequests: [item], contacts: [])
        lastViewed = Self.referenceNow.addingTimeInterval(-60)

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    // MARK: Established contacts

    func testTheirAcceptOfOurRequestPosts() async {
        // Incoming row newer than outgoing: they reciprocated.
        let item = makeItem(idByte: 0xbb, relationship: .established,
                            username: "bob", age: 60,
                            incomingAge: 60, outgoingAge: 3_600)
        snapshot = .init(incomingRequests: [], contacts: [item])

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, "contact.accepted.\(idHex(0xbb))")
        XCTAssertEqual(request.content.body,
                       String(format: NSLocalizedString("%@ accepted your contact request", comment: "DashPay Notifications"), "bob"))
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo), .dashPayNotifications)
    }

    func testOurOwnAcceptDoesNotPost() async {
        // Outgoing row newer than incoming: WE accepted — the user did it
        // themselves, nothing to announce.
        let item = makeItem(idByte: 0xcc, relationship: .established,
                            age: 60, incomingAge: 3_600, outgoingAge: 60)
        snapshot = .init(incomingRequests: [], contacts: [item])

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    // MARK: App-state policy

    func testForegroundSuppressPathConsumes() async {
        appState.isApplicationActive = true
        let item = makeItem(relationship: .incoming, incomingAge: 60)
        snapshot = .init(incomingRequests: [item], contacts: [])

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        // Consumed: the bell showed it live, so a scan after backgrounding
        // cannot post it and the badge never counts it.
        XCTAssertEqual(store.events["contact.request.\(idHex(0xaa))"]?.seen, true)

        appState.isApplicationActive = false
        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }
}

#endif
