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

/// Drives the producer through its injected row source with synthetic
/// `ObservedTransaction` rows — no SwiftData involved — against the real
/// dispatcher over the shared in-memory store and fake center client
/// doubles, so the store's dedup is exercised for real.
final class TransactionNotificationProducerTests: XCTestCase {
    /// Fixed wall clock handed to the producer; rows are stamped relative
    /// to it.
    private static let referenceNow = Date(timeIntervalSince1970: 1_756_000_000)

    private static let crowdNodeDepositAmount = ApiCode.depositReceived.rawValue + CrowdNode.apiOffset

    private var client: FakeUserNotificationCenterClient!
    private var store: InMemoryNotifiedEventStore!
    private var preferences: FakeNotificationPreferenceStore!
    private var dispatcher: NotificationDispatcher!
    private var appState: FakeAppStateProvider!
    private var rows: [ObservedTransaction] = []
    private var syncState: SyncingActivityMonitor.State = .syncDone
    private var watchBodies: [String] = []
    private var producer: TransactionNotificationProducer!

    override func setUp() {
        super.setUp()
        client = FakeUserNotificationCenterClient()
        store = InMemoryNotifiedEventStore()
        preferences = FakeNotificationPreferenceStore()
        appState = FakeAppStateProvider()
        rows = []
        syncState = .syncDone
        watchBodies = []
        let permissions = NotificationPermissionCoordinator(client: client, preferences: preferences)
        dispatcher = NotificationDispatcher(client: client, store: store, permissions: permissions)
        producer = TransactionNotificationProducer(
            dispatcher: dispatcher,
            store: store,
            rowSource: { [weak self] _ in self?.rows ?? [] },
            syncState: { [weak self] in self?.syncState ?? .unknown },
            appState: appState,
            watchBridge: { [weak self] body in self?.watchBodies.append(body) },
            now: { Self.referenceNow })
    }

    /// A synthetic decoded row. `directionRaw` uses the FFI encoding the
    /// wrapper classifies from: 0=incoming, 1=outgoing, 2=internal.
    private func makeRow(txidByte: UInt8 = 0xab,
                         directionRaw: UInt32 = 0,
                         netAmount: Int64 = 150_000,
                         age: TimeInterval = 60,
                         hasTimestamp: Bool = true) -> ObservedTransaction {
        let txid = Data(repeating: txidByte, count: 32)
        let timestamp = Self.referenceNow.addingTimeInterval(-age)
        let wrapped = Transaction(
            syntheticTxid: txid,
            directionRaw: directionRaw,
            netAmount: netAmount,
            fee: nil,
            contextRaw: 1,
            date: timestamp)
        return ObservedTransaction(
            txid: txid,
            txidHexDisplay: String(repeating: String(format: "%02x", txidByte), count: 32),
            outputs: [],
            inputAddresses: [],
            timestamp: hasTimestamp ? timestamp : nil,
            ownOutputsAmount: netAmount > 0 ? UInt64(netAmount) : 0,
            ownOutputAddresses: [],
            isChainAccepted: true,
            context: 1,
            wrapped: wrapped)
    }

    private func expectedId(txidByte: UInt8) -> String {
        "tx." + String(repeating: String(format: "%02x", txidByte), count: 32)
    }

    // MARK: Posting and classification

    func testReceivedRowPostsWithTransactionIdentityAndCopy() async {
        rows = [makeRow(txidByte: 0xab, netAmount: 150_000)]

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        XCTAssertEqual(request.identifier, expectedId(txidByte: 0xab))
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.transactions.rawValue)
        // "Received <amount> (<fiat>)" — the fiat half depends on live
        // rates, so assert the stable parts.
        XCTAssertTrue(request.content.body.contains(UInt64(150_000).formattedDashAmount))
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo),
                       .transactionDetail(txid: Data(repeating: 0xab, count: 32)))
    }

    func testCrowdNodeDepositAmountClassifiesToCrowdNodeKeepingTxIdentity() async {
        rows = [makeRow(txidByte: 0xcd, netAmount: Int64(Self.crowdNodeDepositAmount))]

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        let request = client.addedRequests[0]
        // Classification changes copy and route only — identity is the txid.
        XCTAssertEqual(request.identifier, expectedId(txidByte: 0xcd))
        XCTAssertEqual(request.content.threadIdentifier, NotificationTopic.crowdnode.rawValue)
        XCTAssertEqual(request.content.body,
                       NSLocalizedString("Your deposit to CrowdNode is received.", comment: "CrowdNode"))
        XCTAssertEqual(DeepLinkRoute.decode(fromUserInfo: request.content.userInfo), .staking)
    }

    func testMovedAndSentRowsNeverPost() async {
        rows = [
            makeRow(txidByte: 0x01, directionRaw: 2, netAmount: 0),
            makeRow(txidByte: 0x02, directionRaw: 1, netAmount: -50_000),
        ]

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertTrue(watchBodies.isEmpty)
    }

    func testZeroAmountReceivedRowDoesNotPost() async {
        rows = [makeRow(netAmount: 0)]

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    // MARK: Replay guard

    func testNoPostWhileSyncIsNotDone() async {
        rows = [makeRow()]

        for state in [SyncingActivityMonitor.State.syncing, .syncFailed, .noConnection, .unknown] {
            syncState = state
            await producer.scanAndNotify()
        }

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertTrue(watchBodies.isEmpty)
    }

    func testStaleOrUndatedRowsAreDropped() async {
        rows = [
            makeRow(txidByte: 0x03, age: 11 * 60),
            makeRow(txidByte: 0x04, hasTimestamp: false),
        ]

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testFreshRowWithinWindowPosts() async {
        rows = [makeRow(age: 9 * 60)]

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
    }

    // MARK: App-state policy

    func testForegroundDropsPlainPaymentAndConsumesIt() async {
        appState.isApplicationActive = true
        rows = [makeRow()]

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertTrue(watchBodies.isEmpty)

        // The id was consumed: a rescan after backgrounding must not
        // resurrect a payment the user watched arrive in the feed.
        appState.isApplicationActive = false
        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    func testForegroundStillPostsCrowdNodeDeposit() async {
        appState.isApplicationActive = true
        rows = [makeRow(netAmount: Int64(Self.crowdNodeDepositAmount))]

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
    }

    // MARK: Watch bridge

    func testWatchBridgeMirrorsPostedRowsOnly() async {
        rows = [makeRow(txidByte: 0x05)]

        await producer.scanAndNotify()

        XCTAssertEqual(watchBodies, [client.addedRequests[0].content.body])

        // A row the dispatcher drops (permission gate) does not reach the
        // watch either.
        preferences.userWantsNotifications = false
        rows = [makeRow(txidByte: 0x06)]
        await producer.scanAndNotify()

        XCTAssertEqual(watchBodies.count, 1)
    }

    // MARK: Dedup across signals

    func testRowSeenByTwoSignalsPostsOnce() async {
        rows = [makeRow()]

        // Two scans stand in for the same row surfacing through two signals
        // (SwiftData save + projection change); the dispatcher's store is
        // the only dedup.
        await producer.scanAndNotify()
        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        XCTAssertEqual(watchBodies.count, 1)
    }
}
