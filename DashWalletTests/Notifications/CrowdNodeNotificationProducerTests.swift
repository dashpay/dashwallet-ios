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
@testable import dashpay

/// Exercises the producer against the real dispatcher over the in-memory
/// store, so the stable-id re-arm is proven against the actual dedup.
/// The `showNotificationOnResult` guard is NOT here by design — it stays in
/// `CrowdNode.notifyIfNeeded` (screen-driven state the CrowdNode
/// controllers toggle), so every message that reaches this seam posts.
final class CrowdNodeNotificationProducerTests: XCTestCase {
    private var client: FakeUserNotificationCenterClient!
    private var store: InMemoryNotifiedEventStore!
    private var preferences: FakeNotificationPreferenceStore!
    private var dispatcher: NotificationDispatcher!
    private var producer: CrowdNodeNotificationProducer!

    override func setUp() {
        super.setUp()
        client = FakeUserNotificationCenterClient()
        store = InMemoryNotifiedEventStore()
        preferences = FakeNotificationPreferenceStore()
        let permissions = NotificationPermissionCoordinator(client: client, preferences: preferences)
        dispatcher = NotificationDispatcher(client: client, store: store, permissions: permissions)
        producer = CrowdNodeNotificationProducer(dispatcher: dispatcher, store: store)
    }

    func testPostCarriesCrowdNodeTopicRouteAndPresentation() async {
        let posted = await producer.post(message: "Your CrowdNode account is set up and ready to use!")

        XCTAssertTrue(posted)
        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, CrowdNodeNotificationProducer.resultNotificationID)
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.crowdnode.rawValue)
        XCTAssertEqual(request.content.categoryIdentifier, NotificationTopic.crowdnode.rawValue)
        XCTAssertEqual(request.content.body, "Your CrowdNode account is set up and ready to use!")
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo), .staking)
        XCTAssertEqual(request.content.userInfo[NotificationUserInfoKey.foregroundBehavior] as? String,
                       NotificationForegroundBehavior.banner.rawValue)
    }

    func testRepeatedMessagesAllReachTheClientUnderOneIdentifier() async {
        // A retrying operation: every message is still delivered (the store
        // must not swallow the later ones as duplicates), and all of them
        // share the identifier, so the notification center replaces the
        // delivered banner rather than stacking one per retry.
        await producer.post(message: "Deposit failed")
        await producer.post(message: "Deposit failed")
        await producer.post(message: "Deposit sent")

        XCTAssertEqual(client.addedRequests.count, 3)
        XCTAssertTrue(client.addedRequests.allSatisfy {
            $0.identifier == CrowdNodeNotificationProducer.resultNotificationID
        })
        XCTAssertEqual(client.addedRequests.last?.content.body, "Deposit sent")
    }

    func testRetriesLeaveOneUnseenRowAndBadgeOne() async {
        await producer.post(message: "error 1")
        await producer.post(message: "error 2")
        await producer.post(message: "error 3")

        XCTAssertEqual(store.events.count, 1)
        let unseen = await store.unseenCount()
        XCTAssertEqual(unseen, 1)
        XCTAssertEqual(client.addedRequests.map { $0.content.badge?.intValue }, [1, 1, 1])
    }

    func testResultAfterTheLastWasSeenIsUnseenAgain() async {
        store.seed(id: CrowdNodeNotificationProducer.resultNotificationID, topic: .crowdnode, seen: true)

        let posted = await producer.post(message: "Your CrowdNode address has been confirmed.")

        XCTAssertTrue(posted)
        XCTAssertEqual(store.events[CrowdNodeNotificationProducer.resultNotificationID]?.seen, false)
        XCTAssertEqual(client.addedRequests.first?.content.badge?.intValue, 1)
    }

    func testConcurrentPostsAreAllDelivered() async {
        // Two results racing for the same row: the re-arm is serialized with
        // its post, so neither is dropped as the other's duplicate.
        async let first = producer.post(message: "first")
        async let second = producer.post(message: "second")
        let results = await [first, second]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(client.addedRequests.count, 2)
        XCTAssertEqual(store.events.count, 1)
    }

    func testPermissionGateStillApplies() async {
        preferences.userWantsNotifications = false

        let posted = await producer.post(message: "error text")

        XCTAssertFalse(posted)
        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testPostResultTrampolineDeliversAsynchronously() {
        let delivered = expectation(description: "request added")
        client.onAdd = { _ in delivered.fulfill() }

        producer.postResult(message: "Your CrowdNode address has been confirmed.")

        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(client.addedRequests.first?.content.body,
                       "Your CrowdNode address has been confirmed.")
    }

    func testOtherTopicsRowsAreUntouchedByTheReArm() async {
        store.seed(id: "tx.abc", topic: .transactions)

        await producer.post(message: "message")

        XCTAssertNotNil(store.events["tx.abc"])
        XCTAssertEqual(store.unmarkedIds, [CrowdNodeNotificationProducer.resultNotificationID])
    }
}
