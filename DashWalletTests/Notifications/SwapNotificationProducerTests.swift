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

import Combine
import XCTest
import UserNotifications
@testable import dashpay

/// Feeds synthetic order sets through `process` (and once through the
/// injected publisher) against the real dispatcher over the in-memory
/// store, so the store-as-transition-edge-detector design is exercised for
/// real.
final class SwapNotificationProducerTests: XCTestCase {
    /// Fixed wall clock handed to the producer; orders are stamped
    /// relative to it.
    private static let referenceNow = Date(timeIntervalSince1970: 1_756_000_000)

    private var client: FakeUserNotificationCenterClient!
    private var store: InMemoryNotifiedEventStore!
    private var preferences: FakeNotificationPreferenceStore!
    private var dispatcher: NotificationDispatcher!
    private var appState: FakeAppStateProvider!
    private var swapUIVisible = false
    private var ordersSubject: PassthroughSubject<[SwapOrder], Never>!
    private var producer: SwapNotificationProducer!

    override func setUp() {
        super.setUp()
        client = FakeUserNotificationCenterClient()
        store = InMemoryNotifiedEventStore()
        preferences = FakeNotificationPreferenceStore()
        appState = FakeAppStateProvider()
        swapUIVisible = false
        ordersSubject = PassthroughSubject()
        let permissions = NotificationPermissionCoordinator(client: client, preferences: preferences)
        dispatcher = NotificationDispatcher(client: client, store: store, permissions: permissions)
        producer = SwapNotificationProducer(
            dispatcher: dispatcher,
            store: store,
            ordersPublisher: { [ordersSubject] in ordersSubject!.eraseToAnyPublisher() },
            appState: appState,
            swapUIVisible: { [weak self] in self?.swapUIVisible ?? false },
            now: { Self.referenceNow })
    }

    private func makeOrder(id: String = "order-1",
                           status: SwapOrderStatus,
                           finalisedAge: TimeInterval? = 60,
                           fromAsset: String = "DASH",
                           toAsset: String = "BTC.BTC") -> SwapOrder {
        SwapOrder(
            id: id,
            direction: "sell",
            service: "maya",
            fromAsset: fromAsset,
            toAsset: toAsset,
            toAddress: "addr",
            status: status,
            timestamp: Int64(Self.referenceNow.timeIntervalSince1970 * 1000) - 3_600_000,
            finalisedAt: finalisedAge.map { Int64(Self.referenceNow.addingTimeInterval(-$0).timeIntervalSince1970) } ?? -1)
    }

    // MARK: Terminal transitions

    func testTerminalOrderPostsOnceAcrossRepeatedRefreshes() async {
        let order = makeOrder(status: .completed)

        // A terminal order re-emitted by N refreshes: the store dedup is
        // the transition-edge detector.
        await producer.process([order])
        await producer.process([order])

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, "swap.order-1")
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.swap.rawValue)
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo),
                       .swapOrder(id: "order-1"))
    }

    func testBodyNamesOutcomeAndPair() async {
        await producer.process([makeOrder(id: "a", status: .completed)])
        await producer.process([makeOrder(id: "b", status: .refunded)])
        await producer.process([makeOrder(id: "c", status: .failed)])
        await producer.process([makeOrder(id: "d", status: .expired)])

        XCTAssertEqual(client.addedRequests.count, 4)
        let bodies = client.addedRequests.map(\.content.body)
        XCTAssertTrue(bodies.allSatisfy { $0.contains("DASH/BTC") })
        // Four distinct outcomes, four distinct messages.
        XCTAssertEqual(Set(bodies).count, 4)
    }

    func testNonTerminalOrdersNeverPost() async {
        let orders = [
            makeOrder(id: "n1", status: .notStarted),
            makeOrder(id: "n2", status: .pending),
            makeOrder(id: "n3", status: .swapping),
            makeOrder(id: "n4", status: .unknown),
        ]

        await producer.process(orders)

        XCTAssertTrue(client.addedRequests.isEmpty)
        // Not even recorded: a later terminal transition must still post.
        XCTAssertTrue(store.events.isEmpty)
    }

    // MARK: Replay guard

    func testStaleFinalisationIsConsumedWithoutPosting() async {
        let order = makeOrder(status: .completed, finalisedAge: 11 * 60)

        await producer.process([order])

        XCTAssertTrue(client.addedRequests.isEmpty)
        // Recorded as known-and-seen, so no later pass can post it and the
        // badge never counts it.
        XCTAssertEqual(store.events["swap.order-1"]?.seen, true)
    }

    func testUnknownFinalisationCannotProveFreshnessAndDoesNotPost() async {
        let order = makeOrder(status: .completed, finalisedAge: nil)

        await producer.process([order])

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertEqual(store.events["swap.order-1"]?.seen, true)
    }

    // MARK: App-state policy

    func testForegroundOnSwapUIIsConsumedAndStaysSilentAfterBackgrounding() async {
        appState.isApplicationActive = true
        swapUIVisible = true
        let order = makeOrder(status: .completed)

        await producer.process([order])

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertEqual(store.events["swap.order-1"]?.seen, true)

        // The user watched the swap-status screen finish; a re-emission
        // after backgrounding cannot resurrect it.
        appState.isApplicationActive = false
        swapUIVisible = false
        await producer.process([order])

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testForegroundOffSwapUIPostsBanner() async {
        appState.isApplicationActive = true
        swapUIVisible = false

        await producer.process([makeOrder(status: .completed)])

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, "swap.order-1")
        // `.banner` rides in userInfo so `NotificationLifecycle.willPresent`
        // shows it over the non-swap screen the user is on.
        XCTAssertEqual(request.content.userInfo[NotificationUserInfoKey.foregroundBehavior] as? String,
                       NotificationForegroundBehavior.banner.rawValue)
    }

    func testBackgroundedPostsEvenWhileVisibilityFlagIsTrue() async {
        // A stale visible flag (e.g. the status screen was frontmost when
        // the app was backgrounded — viewWillDisappear never fires) must
        // not suppress: visibility only matters while active.
        appState.isApplicationActive = false
        swapUIVisible = true

        await producer.process([makeOrder(status: .completed)])

        XCTAssertEqual(client.addedRequests.count, 1)
        XCTAssertEqual(client.addedRequests[0].identifier, "swap.order-1")
    }

    // MARK: Signal wiring

    func testStartSubscribesToTheOrdersPublisher() {
        let delivered = expectation(description: "request added")
        client.onAdd = { _ in delivered.fulfill() }

        producer.start()
        ordersSubject.send([makeOrder(status: .completed)])

        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(client.addedRequests.first?.identifier, "swap.order-1")
    }
}

// MARK: - SwapStatusUIVisibilityTests

/// Exercises the visible-screen counter on `SwapTrackingService.shared`
/// (the production `swapUIVisible` source). The singleton's counter is
/// process-global, so every path here rebalances it back to zero.
final class SwapStatusUIVisibilityTests: XCTestCase {
    func testStackedScreensKeepVisibilityUntilTheLastDisappears() {
        let service = SwapTrackingService.shared
        XCTAssertFalse(service.isStatusUIVisible)

        // Two status screens overlap mid-transition (retry rebuilds the
        // stack): one screen leaving must not clear the other's mark.
        service.statusScreenWillAppear()
        service.statusScreenWillAppear()
        XCTAssertTrue(service.isStatusUIVisible)

        service.statusScreenWillDisappear()
        XCTAssertTrue(service.isStatusUIVisible)

        service.statusScreenWillDisappear()
        XCTAssertFalse(service.isStatusUIVisible)
    }

    func testUnbalancedDisappearCannotPreCancelALaterAppear() {
        let service = SwapTrackingService.shared
        XCTAssertFalse(service.isStatusUIVisible)

        // The count clamps at zero, so a stray disappear leaves the next
        // appear/disappear pair working normally.
        service.statusScreenWillDisappear()
        XCTAssertFalse(service.isStatusUIVisible)

        service.statusScreenWillAppear()
        XCTAssertTrue(service.isStatusUIVisible)

        service.statusScreenWillDisappear()
        XCTAssertFalse(service.isStatusUIVisible)
    }
}
