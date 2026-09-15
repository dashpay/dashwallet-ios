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
    /// Every `firstSeen` floor the producer asked the row source for.
    private var rowFloors: [UInt64] = []
    /// Row offsets each fetch asked for — how a paged catch-up sweep is
    /// told apart from a single-fetch signal-driven scan.
    private var rowOffsets: [Int] = []
    /// What `DWGlobalOptions.notificationCatchUpDate` reads in production.
    private var catchUpBoundary: Date?
    private var watchBodies: [String] = []
    private var producer: TransactionNotificationProducer!

    override func setUp() {
        super.setUp()
        client = FakeUserNotificationCenterClient()
        store = InMemoryNotifiedEventStore()
        preferences = FakeNotificationPreferenceStore()
        appState = FakeAppStateProvider()
        rows = []
        rowFloors = []
        rowOffsets = []
        catchUpBoundary = nil
        watchBodies = []
        let permissions = NotificationPermissionCoordinator(client: client, preferences: preferences)
        dispatcher = NotificationDispatcher(client: client, store: store, permissions: permissions)
        producer = TransactionNotificationProducer(
            dispatcher: dispatcher,
            store: store,
            rowSource: { [weak self] floor, offset in
                self?.rowFloors.append(floor)
                self?.rowOffsets.append(offset)
                // Mirrors the production sources: newest-first, one fetch's
                // worth at a time, from the offset the caller paged to.
                let all = self?.rows ?? []
                return Array(all.dropFirst(offset).prefix(TransactionNotificationProducer.scanFetchLimit))
            },
            appState: appState,
            watchBridge: { [weak self] body in self?.watchBodies.append(body) },
            catchUpBoundary: { [weak self] in self?.catchUpBoundary },
            now: { Self.referenceNow })
    }

    private static func epoch(_ secondsAgo: TimeInterval) -> UInt64 {
        UInt64(referenceNow.addingTimeInterval(-secondsAgo).timeIntervalSince1970)
    }

    /// A synthetic decoded row. `directionRaw` uses the FFI encoding the
    /// wrapper classifies from: 0=incoming, 1=outgoing, 2=internal.
    ///
    /// `age` is the row's device-clock `firstSeen`; `minedAge`, when given,
    /// makes the row mined (`blockHeight` 1) with that block timestamp —
    /// the two diverge exactly the way a restore burst makes them diverge.
    private func makeRow(txidByte: UInt8 = 0xab,
                         directionRaw: UInt32 = 0,
                         netAmount: Int64 = 150_000,
                         age: TimeInterval = 60,
                         hasTimestamp: Bool = true,
                         minedAge: TimeInterval? = nil,
                         blockHeight: UInt32? = nil) -> ObservedTransaction {
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
            blockHeight: blockHeight ?? (minedAge == nil ? 0 : 1),
            minedAt: minedAge.map { Self.referenceNow.addingTimeInterval(-$0) },
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

    /// The payout of the app's own Shielded → Core withdrawal is received on
    /// L1 but is an internal transfer — no "Received" notification, no watch
    /// notice.
    func testShieldedWithdrawalPayoutDoesNotPost() async {
        producer = TransactionNotificationProducer(
            dispatcher: dispatcher,
            store: store,
            rowSource: { [weak self] _, _ in self?.rows ?? [] },
            appState: appState,
            watchBridge: { [weak self] body in self?.watchBodies.append(body) },
            catchUpBoundary: { nil },
            isShieldedWithdrawalPayout: { _ in true },
            now: { Self.referenceNow })
        rows = [makeRow(txidByte: 0x09, netAmount: 150_000)]

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

    /// A row whose `firstSeen` is recent — first sighted unmined on the
    /// device clock — while its block is old. `firstSeen` must not be able
    /// to vouch for it.
    func testMinedRowWithOldBlockDoesNotPostDespiteFreshFirstSeen() async {
        rows = [makeRow(age: 0, minedAge: 30 * 24 * 60 * 60)]

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertTrue(watchBodies.isEmpty)
    }

    /// A row that claims a block but carries no block timestamp proves
    /// nothing about when it arrived.
    func testMinedRowWithoutBlockTimestampDoesNotPost() async {
        rows = [makeRow(age: 0, blockHeight: 2_500_000)]

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    /// A payment mined into a block that was just found still notifies.
    func testFreshlyMinedRowPosts() async {
        rows = [makeRow(age: 0, minedAge: 30)]

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
    }

    /// The regression this producer was rewritten for: a payment arriving
    /// while the SDK is mid-sync (which is what an incoming transaction
    /// makes it do) is unmined, so nothing about the sync state may stop
    /// it. No sync seam is injected at all — the default production
    /// `SyncingActivityMonitor` state in a unit-test process is
    /// `.unknown`, and this posts regardless.
    func testUnminedRowPostsRegardlessOfSyncState() async {
        rows = [makeRow(txidByte: 0x07, age: 5)]

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        XCTAssertEqual(client.addedRequests[0].identifier, expectedId(txidByte: 0x07))
    }

    // MARK: Catch-up window

    func testCatchUpWithoutABoundaryKeepsTheFreshnessWindow() async {
        rows = [makeRow(txidByte: 0x10, age: 11 * 60, minedAge: 11 * 60),
                makeRow(txidByte: 0x11, age: 9 * 60, minedAge: 9 * 60)]

        await producer.scanAndNotify(since: nil)

        XCTAssertEqual(rowFloors.first, Self.epoch(TransactionNotificationProducer.freshnessWindow))
        XCTAssertEqual(client.addedRequests.map(\.identifier), [expectedId(txidByte: 0x11)])
    }

    func testCatchUpReachesBackToTheBoundary() async {
        rows = [makeRow(txidByte: 0x12, age: 30 * 60, minedAge: 30 * 60),
                makeRow(txidByte: 0x13, age: 90 * 60, minedAge: 90 * 60)]

        await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-60 * 60))

        XCTAssertEqual(rowFloors.first, Self.epoch(60 * 60))
        XCTAssertEqual(client.addedRequests.map(\.identifier), [expectedId(txidByte: 0x12)])
    }

    func testCatchUpIsFlooredAtOneDay() async {
        rows = [makeRow(txidByte: 0x14, age: 23 * 60 * 60, minedAge: 23 * 60 * 60),
                makeRow(txidByte: 0x15, age: 25 * 60 * 60, minedAge: 25 * 60 * 60)]

        await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-72 * 60 * 60))

        XCTAssertEqual(rowFloors.first, Self.epoch(TransactionNotificationProducer.maxCatchUpWindow))
        XCTAssertEqual(client.addedRequests.map(\.identifier), [expectedId(txidByte: 0x14)])
    }

    /// A boundary inside the freshness window never narrows it.
    func testCatchUpNeverNarrowsTheFreshnessWindow() async {
        rows = [makeRow(txidByte: 0x16, age: 5 * 60, minedAge: 5 * 60)]

        await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-60))

        XCTAssertEqual(rowFloors.first, Self.epoch(TransactionNotificationProducer.freshnessWindow))
        XCTAssertEqual(client.addedRequests.count, 1)
    }

    // MARK: Catch-up paging

    /// Both row sources return newest-first under a per-fetch cap, so a
    /// window wider than one fetch hides its OLDEST rows behind that cap. The
    /// sweep — the only caller that advances `notificationCatchUpDate` — pages
    /// until the window runs out, and reports that it reached the end.
    func testACatchUpSweepPagesUntilTheWindowIsExhausted() async {
        let page = TransactionNotificationProducer.scanFetchLimit
        rows = (0..<(page + 5)).map {
            makeRow(txidByte: UInt8($0), age: 30 * 60, minedAge: 30 * 60)
        }

        let covered = await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-60 * 60))

        XCTAssertTrue(covered)
        XCTAssertEqual(rowOffsets, [0, page])
        XCTAssertEqual(client.addedRequests.count, page + 5)
    }

    /// A signal-driven scan reads ONE fetch: it fires on every persistence
    /// signal, and the rows it leaves are not lost because it moves no
    /// boundary. It says the window is unexhausted so nothing advances over
    /// what it did not read.
    func testASignalDrivenScanReadsOneFetchAndReportsTheWindowUnexhausted() async {
        let page = TransactionNotificationProducer.scanFetchLimit
        rows = (0..<(page + 5)).map {
            makeRow(txidByte: UInt8($0), age: 5 * 60, minedAge: 5 * 60)
        }

        let covered = await producer.scanAndNotify()

        XCTAssertFalse(covered)
        XCTAssertEqual(rowOffsets, [0])
    }

    /// A window that fits in one fetch is exhausted by it — no second read.
    func testAWindowInsideOneFetchIsReportedCovered() async {
        rows = [makeRow(txidByte: 0x21, age: 30 * 60, minedAge: 30 * 60)]

        let covered = await producer.scanAndNotify(since: Self.referenceNow.addingTimeInterval(-60 * 60))

        XCTAssertTrue(covered)
        XCTAssertEqual(rowOffsets, [0])
    }

    /// A payment mined while the app slept and synced after it opened is
    /// older than the freshness window, so no foreground scan posts it — the
    /// user sees it on Home. A later background sweep reaching back to the
    /// boundary must not announce it then.
    func testPaymentShownInForegroundIsNotAnnouncedByALaterCatchUp() async {
        let boundary = Self.referenceNow.addingTimeInterval(-48 * 60 * 60)
        catchUpBoundary = boundary
        rows = [makeRow(txidByte: 0x17, age: 3 * 60 * 60, minedAge: 3 * 60 * 60)]

        appState.isApplicationActive = true
        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertEqual(store.events[expectedId(txidByte: 0x17)]?.seen, true)

        appState.isApplicationActive = false
        await producer.scanAndNotify(since: boundary)

        XCTAssertTrue(client.addedRequests.isEmpty)
    }

    /// The control for the test above: a payment the app never showed is
    /// still announced by the catch-up sweep.
    func testCatchUpStillAnnouncesAPaymentTheAppNeverShowed() async {
        let boundary = Self.referenceNow.addingTimeInterval(-48 * 60 * 60)
        catchUpBoundary = boundary
        rows = [makeRow(txidByte: 0x18, age: 3 * 60 * 60, minedAge: 3 * 60 * 60)]

        await producer.scanAndNotify(since: boundary)

        XCTAssertEqual(client.addedRequests.map(\.identifier), [expectedId(txidByte: 0x18)])
    }

    // MARK: App-state policy

    func testForegroundDropsPlainPaymentAndConsumesIt() async {
        appState.isApplicationActive = true
        rows = [makeRow()]

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        // The phone stays quiet, the watch still shows the payment.
        XCTAssertEqual(watchBodies.count, 1)

        // The id was consumed: a rescan after backgrounding must not
        // resurrect a payment the user watched arrive in the feed — on the
        // phone or on the watch.
        appState.isApplicationActive = false
        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertEqual(watchBodies.count, 1)
    }

    func testForegroundStillPostsCrowdNodeDeposit() async {
        appState.isApplicationActive = true
        rows = [makeRow(netAmount: Int64(Self.crowdNodeDepositAmount))]

        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
    }

    // MARK: Watch bridge

    func testWatchBridgeMirrorsPostedRowWithItsBody() async {
        rows = [makeRow(txidByte: 0x05)]

        await producer.scanAndNotify()

        XCTAssertEqual(watchBodies, [client.addedRequests[0].content.body])
    }

    /// The watch shows every received payment, as the retired balance
    /// notifier did — not only the ones the phone was allowed to notify.
    func testWatchBridgeMirrorsFreshReceivedRowWhenNotificationsAreOff() async {
        preferences.userWantsNotifications = false
        rows = [makeRow(txidByte: 0x06, netAmount: 150_000)]

        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertEqual(watchBodies.count, 1)
        XCTAssertTrue(watchBodies[0].contains(UInt64(150_000).formattedDashAmount))
    }

    func testWatchBridgeMirrorsOnceAcrossRescansAndALaterGrant() async {
        preferences.userWantsNotifications = false
        rows = [makeRow(txidByte: 0x08)]

        await producer.scanAndNotify()
        await producer.scanAndNotify()

        // Notifications turned on: the next scan posts the row to the phone,
        // but the watch already has it.
        preferences.userWantsNotifications = true
        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.count, 1)
        XCTAssertEqual(watchBodies.count, 1)
    }

    func testWatchBridgeMirrorsPlatformActivityWhenNotificationsAreOff() async {
        preferences.userWantsNotifications = false
        let record = PlatformAddressActivityRecord(
            id: 42,
            walletId: Data(repeating: 0x01, count: 32),
            networkRaw: 0,
            address: "tdash1platformtest",
            amountDuffs: 70_000,
            balanceAfterDuffs: 70_000,
            observedAt: Self.referenceNow.addingTimeInterval(-30))
        producer = TransactionNotificationProducer(
            dispatcher: dispatcher,
            store: store,
            rowSource: { _, _ in [] },
            platformActivitySource: { _, _ in [record] },
            appState: appState,
            watchBridge: { [weak self] body in self?.watchBodies.append(body) },
            catchUpBoundary: { nil },
            now: { Self.referenceNow })

        await producer.scanAndNotify()
        await producer.scanAndNotify()

        XCTAssertTrue(client.addedRequests.isEmpty)
        XCTAssertEqual(watchBodies.count, 1)
    }

    // MARK: Dedup across signals

    /// The same txid first surfaces unmined, then again once mined: one
    /// notification, one watch notice.
    func testUnconfirmedThenMinedRowPostsAndMirrorsOnce() async {
        rows = [makeRow(txidByte: 0x19, age: 60)]
        await producer.scanAndNotify()

        rows = [makeRow(txidByte: 0x19, age: 30, minedAge: 30)]
        await producer.scanAndNotify()

        XCTAssertEqual(client.addedRequests.map(\.identifier), [expectedId(txidByte: 0x19)])
        XCTAssertEqual(watchBodies.count, 1)
    }

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
