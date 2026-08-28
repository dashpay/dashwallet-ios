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

/// Exercises the producer against the real dispatcher over the in-memory
/// store, so the event-scoped-id design is proven against the actual dedup.
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
        producer = CrowdNodeNotificationProducer(dispatcher: dispatcher)
    }

    func testPostCarriesCrowdNodeTopicRouteAndPresentation() async {
        let posted = await producer.post(message: "Your CrowdNode account is set up and ready to use!")

        XCTAssertTrue(posted)
        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertTrue(request.identifier.hasPrefix("crowdnode.result."))
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.crowdnode.rawValue)
        XCTAssertEqual(request.content.categoryIdentifier, NotificationTopic.crowdnode.rawValue)
        XCTAssertEqual(request.content.body, "Your CrowdNode account is set up and ready to use!")
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo), .staking)
        XCTAssertEqual(request.content.userInfo[NotificationUserInfoKey.foregroundBehavior] as? String,
                       NotificationForegroundBehavior.banner.rawValue)
    }

    func testRepeatedIdenticalMessagesBothReachTheClient() async {
        // The bug the event-scoped id fixes: under the fixed legacy
        // "CrowdNode" id, the store dedup swallowed every message after
        // the first one.
        await producer.post(message: "Deposit sent")
        await producer.post(message: "Deposit sent")

        XCTAssertEqual(client.addedRequests.count, 2)
        XCTAssertNotEqual(client.addedRequests[0].identifier, client.addedRequests[1].identifier)
        XCTAssertTrue(client.addedRequests.allSatisfy { $0.identifier.hasPrefix("crowdnode.result.") })
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

    func testInjectedEventIdIsUsedVerbatim() async {
        let pinned = CrowdNodeNotificationProducer(dispatcher: dispatcher,
                                                   makeEventId: { "crowdnode.result.pinned" })

        await pinned.post(message: "message")

        XCTAssertEqual(client.addedRequests.first?.identifier, "crowdnode.result.pinned")
        XCTAssertNotNil(store.events["crowdnode.result.pinned"])
    }
}
