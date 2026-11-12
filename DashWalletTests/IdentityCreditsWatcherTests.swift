//
//  IdentityCreditsWatcherTests.swift
//  DashWalletTests
//
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

import SwiftDashSDK
import XCTest
@testable import dashpay

/// The Identity option's watch: a fresh Starting balance, checks on the
/// Platform cadence, own top-ups subtracted, and one Receipt for a rise of at
/// least 1 duff (AC-05, AC-06, AC-08, AC-13; sad.md QG-1).
@MainActor
final class IdentityCreditsWatcherTests: XCTestCase {
    private enum Offline: Error { case unreachable }

    /// Answers reads from a queue; `hold()` makes the next read wait until
    /// `release()`. Main-actor bound like the watcher, so a release can never
    /// slip between a read and its hold.
    @MainActor
    private final class FakeSource {
        var answers: [Result<UInt64, Error>] = []
        private(set) var reads: [IdentityCreditsWatcher.Session] = []
        private var held: CheckedContinuation<Void, Never>?
        private var holdNext = false
        private var releasedEarly = false

        func hold() { holdNext = true }

        func release() {
            if let held {
                held.resume()
                self.held = nil
            } else {
                releasedEarly = true
            }
        }

        func read(_ session: IdentityCreditsWatcher.Session) async -> Result<UInt64, Error> {
            reads.append(session)
            let answer = answers.isEmpty ? .failure(Offline.unreachable) : answers.removeFirst()
            if holdNext {
                holdNext = false
                if releasedEarly {
                    releasedEarly = false
                } else {
                    await withCheckedContinuation { held = $0 }
                }
            }
            return answer
        }

        /// Yields until `count` reads have started.
        func waitForReads(_ count: Int) async {
            while reads.count < count { await Task.yield() }
        }
    }

    /// Stores the tick instead of running it on a timer. The handle it returns
    /// only sleeps, so its cancellation is readable at once.
    @MainActor
    private final class ManualScheduler {
        private(set) var interval: TimeInterval?
        private(set) var scheduledCount = 0
        private var tick: (@MainActor () async -> Void)?
        private var timer: Task<Void, Never>?

        var cancelled: Bool { timer?.isCancelled ?? false }
        var isRunning: Bool { timer.map { !$0.isCancelled } ?? false }

        func schedule(_ interval: TimeInterval, _ tick: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
            self.interval = interval
            self.tick = tick
            scheduledCount += 1
            let timer = Task { _ = try? await Task.sleep(nanoseconds: 3_600_000_000_000) }
            self.timer = timer
            return timer
        }

        func fire() async { await tick?() }
    }

    private let session = IdentityCreditsWatcher.Session(
        walletId: Data(repeating: 1, count: 32), network: .testnet, identityId: Data(repeating: 2, count: 32))
    private let otherSession = IdentityCreditsWatcher.Session(
        walletId: Data(repeating: 3, count: 32), network: .testnet, identityId: Data(repeating: 4, count: 32))

    // XCTest makes a fresh instance per test, so these are per test too.
    private let source = FakeSource()
    private let scheduler = ManualScheduler()
    private let center = NotificationCenter()
    private let inFlight = IdentityTopUpsInFlight()
    private lazy var watcher = IdentityCreditsWatcher(
        read: { [source] in await source.read($0) },
        schedule: { [scheduler] in scheduler.schedule($0, $1) },
        center: center,
        inFlight: inFlight)

    override func setUp() async throws {
        watcher.setGateOpen(true)
    }

    private func key(_ session: IdentityCreditsWatcher.Session) -> IdentityTopUpsInFlight.Key {
        .init(walletId: session.walletId, network: session.network, identityId: session.identityId)
    }

    private func answer(_ values: UInt64...) {
        source.answers += values.map { .success($0) }
    }

    private func topUp(after balanceAfter: UInt64, supplied: UInt64, for session: IdentityCreditsWatcher.Session) {
        IdentityTopUpDidComplete(
            walletId: session.walletId, network: session.network, identityId: session.identityId,
            balanceAfter: balanceAfter, suppliedCredits: supplied)
            .post(to: center)
    }

    // MARK: Starting balance

    func testChecksRunOnThePlatformCadence() {
        watcher.start(session)
        XCTAssertEqual(scheduler.interval, AttendedReceiveRefreshPolicy.platformInterval)
    }

    func testNotWatchingUntilTheFirstReadSucceedsThenThatReadIsTheStartingBalance() async {
        watcher.start(session)
        source.answers = [.failure(Offline.unreachable)]
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .notWatching)

        answer(10_000, 11_000)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 1))
    }

    // MARK: Receipt decision

    func testTwoPaymentsBetweenChecksGiveOneReceiptForTheirSum() async {
        watcher.start(session)
        answer(10_000, 10_000 + 3_000_000 + 2_000_500)
        await scheduler.fire()
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 5_000))
    }

    func testARiseBelowOneDuffWaitsUntilItAddsUpToOne() async {
        watcher.start(session)
        answer(10_000, 10_999, 11_000)
        await scheduler.fire()
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 1))
    }

    func testUnchangedBalanceRaisesNothing() async {
        watcher.start(session)
        answer(10_000, 10_000)
        await scheduler.fire()
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
    }

    func testALowerBalanceBecomesTheStartingBalance() async {
        watcher.start(session)
        answer(10_000, 8_000, 9_000)
        await scheduler.fire()
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 1))
    }

    func testAReceiptEndsTheSession() async {
        watcher.start(session)
        answer(10_000, 20_000, 40_000)
        await scheduler.fire()
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 10))
        let readsAtReceipt = source.reads.count
        await scheduler.fire()
        XCTAssertEqual(source.reads.count, readsAtReceipt)
        XCTAssertEqual(watcher.state, .received(duffs: 10))
    }

    // MARK: Own top-ups

    func testOwnTopUpRaisesTheStartingBalance() async {
        watcher.start(session)
        answer(10_000, 15_000, 16_000)
        await scheduler.fire()
        topUp(after: 15_000, supplied: 5_000, for: session)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 1))
    }

    func testTopUpOfAnotherIdentityIsIgnored() async {
        watcher.start(session)
        answer(10_000, 15_000)
        await scheduler.fire()
        topUp(after: 15_000, supplied: 5_000, for: otherSession)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 5))
    }

    func testTopUpCountsWhileTheCardIsCovered() async {
        watcher.start(session)
        answer(10_000, 15_000)
        await scheduler.fire()
        watcher.setGateOpen(false)
        topUp(after: 15_000, supplied: 5_000, for: session)
        watcher.setGateOpen(true)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
    }

    /// A read that started before the top-up landed can return the old
    /// balance; taking it would lower the Starting balance and turn the
    /// top-up into a Receipt on the next check.
    func testTopUpDropsTheReadInFlight() async {
        watcher.start(session)
        answer(10_000, 10_000, 15_000)
        await scheduler.fire()
        source.hold()
        let readsBefore = source.reads.count
        async let inFlight: Void = scheduler.fire()
        await source.waitForReads(readsBefore + 1)
        topUp(after: 15_000, supplied: 5_000, for: session)
        source.release()
        await inFlight
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
    }

    /// Platform raises the balance a little before the top-up call returns: a
    /// check in that window must not take the wallet's own top-up for a
    /// payment (review-2026-11-10-r3 Q1).
    func testARiseSeenBeforeTheOwnTopUpIsAnnouncedRaisesNoReceipt() async {
        watcher.start(session)
        answer(10_000, 15_000, 15_000, 16_000)
        await scheduler.fire()
        inFlight.begin(key(session))
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        topUp(after: 15_000, supplied: 5_000, for: session)
        inFlight.end(key(session))
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 1))
    }

    /// A top-up started before the option was opened (the username flow
    /// dismisses while its top-up runs) may or may not be in the first read,
    /// so the Starting balance waits for it to end.
    func testATopUpRunningWhenTheWatchStartsDelaysTheStartingBalance() async {
        inFlight.begin(key(session))
        watcher.start(session)
        answer(10_000, 15_000, 16_000)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .notWatching)
        topUp(after: 15_000, supplied: 5_000, for: session)
        inFlight.end(key(session))
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 1))
    }

    /// A top-up that throws announces nothing; once it ends, a rise is a
    /// Receipt again (the accepted limit for a top-up that failed after
    /// Platform carried it out).
    func testATopUpThatEndsUnannouncedReleasesTheHold() async {
        watcher.start(session)
        answer(10_000, 15_000, 15_000)
        await scheduler.fire()
        inFlight.begin(key(session))
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        inFlight.end(key(session))
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 5))
    }

    /// A spend seen while a top-up runs lowers the Starting balance; the
    /// top-up's own credits must still not come back as a Receipt
    /// (review-2026-11-11-r1 S1).
    func testADecreaseSeenWhileATopUpRunsDoesNotTurnTheTopUpIntoAReceipt() async {
        watcher.start(session)
        answer(20_000, 10_000, 15_000, 16_000)
        await scheduler.fire()
        inFlight.begin(key(session))
        await scheduler.fire()
        topUp(after: 15_000, supplied: 5_000, for: session)
        inFlight.end(key(session))
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .watching)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 1))
    }

    /// A Payer's credits that land while a top-up runs are in the balance it
    /// returns; only the part beyond the credits it was handed (its fee) can
    /// be taken for the top-up's.
    func testPayerCreditsInTheTopUpsBalanceStillRaiseAReceipt() async {
        watcher.start(session)
        answer(10_000, 17_000)
        await scheduler.fire()
        inFlight.begin(key(session))
        topUp(after: 17_000, supplied: 5_500, for: session)
        inFlight.end(key(session))
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 1))
    }

    func testATopUpOfAnotherIdentityDoesNotHoldTheReceipt() async {
        watcher.start(session)
        answer(10_000, 15_000)
        await scheduler.fire()
        inFlight.begin(key(otherSession))
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 5))
    }

    // MARK: Gate and timer

    func testNoTimerRunsWhileTheGateIsClosed() {
        watcher.setGateOpen(false)
        watcher.start(session)
        XCTAssertEqual(scheduler.scheduledCount, 0)
    }

    func testClosingTheGateStopsTheTimer() async {
        watcher.start(session)
        answer(10_000)
        await scheduler.fire()
        watcher.setGateOpen(false)
        XCTAssertTrue(scheduler.cancelled)
    }

    func testOpeningTheGateChecksAtOnceAndKeepsTheStartingBalance() async {
        watcher.start(session)
        answer(10_000, 13_000)
        await scheduler.fire()
        watcher.setGateOpen(false)
        watcher.setGateOpen(true)
        // A new timer, whose first tick is immediate (`repeating`).
        XCTAssertEqual(scheduler.scheduledCount, 2)
        XCTAssertTrue(scheduler.isRunning)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 3))
    }

    /// Closing the gate cancels the timer task and with it the read it runs,
    /// which then answers with a failure. Reopening must check at once, and
    /// the cancelled read's answer must not drop the watching note.
    func testClosingTheGateMidReadDropsThatReadAndReopeningChecksAtOnce() async {
        watcher.start(session)
        answer(10_000)
        await scheduler.fire()
        source.hold()
        source.answers.append(.failure(CancellationError()))
        answer(10_000)
        let readsBefore = source.reads.count
        async let inFlight: Void = scheduler.fire()
        await source.waitForReads(readsBefore + 1)
        watcher.setGateOpen(false)
        watcher.setGateOpen(true)
        await scheduler.fire()
        XCTAssertEqual(source.reads.count, readsBefore + 2)
        source.release()
        await inFlight
        XCTAssertEqual(watcher.state, .watching)
    }

    func testReopeningAnOpenGateKeepsTheTimer() {
        watcher.start(session)
        watcher.setGateOpen(true)
        XCTAssertEqual(scheduler.scheduledCount, 1)
    }

    func testRepeatingTicksBeforeItWaits() async {
        let ticked = expectation(description: "first tick")
        let timer = IdentityCreditsWatcher.repeating(3_600) { ticked.fulfill() }
        await fulfillment(of: [ticked], timeout: 1)
        timer.cancel()
    }

    // MARK: Gaps

    func testNoReadWhileTheGateIsClosed() async {
        watcher.start(session)
        watcher.setGateOpen(false)
        await scheduler.fire()
        XCTAssertTrue(source.reads.isEmpty)
    }

    func testAFailedCheckDropsWatchingAndTheFirstSuccessAfterTheGapRaisesTheReceipt() async {
        watcher.start(session)
        answer(10_000)
        source.answers.append(.failure(Offline.unreachable))
        answer(13_000)
        await scheduler.fire()
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .notWatching)
        await scheduler.fire()
        XCTAssertEqual(watcher.state, .received(duffs: 3))
    }

    // MARK: Sessions

    func testAReplyForAnOldSessionIsDropped() async {
        watcher.start(session)
        answer(10_000)
        await scheduler.fire()
        answer(50_000)
        source.hold()
        let readsBefore = source.reads.count
        async let inFlight: Void = scheduler.fire()
        await source.waitForReads(readsBefore + 1)
        watcher.start(otherSession)
        source.release()
        await inFlight
        XCTAssertEqual(watcher.state, .notWatching)
    }

    func testAReplyAfterStopIsDroppedAndTheTimerCancelled() async {
        watcher.start(session)
        answer(10_000)
        source.hold()
        let readsBefore = source.reads.count
        async let inFlight: Void = scheduler.fire()
        await source.waitForReads(readsBefore + 1)
        watcher.stop()
        source.release()
        await inFlight
        XCTAssertEqual(watcher.state, .notWatching)
        XCTAssertTrue(scheduler.cancelled)
    }

    func testReadsAreForTheStartedSession() async {
        watcher.start(session)
        answer(10_000)
        await scheduler.fire()
        XCTAssertEqual(source.reads, [session])
    }
}
