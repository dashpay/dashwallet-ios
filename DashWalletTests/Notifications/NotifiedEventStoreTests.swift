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

import SQLite
import XCTest
@testable import dashpay

/// Exercises the real SQLite-backed store against a private in-memory
/// database created by the same `AddNotifiedEventsTable` migration the app
/// runs, with an injected clock for the prune-by-age behavior.
final class NotifiedEventStoreTests: XCTestCase {
    /// Mutable wall clock handed to the store.
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)

        func advance(days: Double) {
            now = now.addingTimeInterval(days * 24 * 60 * 60)
        }
    }

    private var clock: Clock!
    private var store: NotifiedEventStore!

    override func setUp() async throws {
        try await super.setUp()
        clock = Clock()
        let clock = clock!
        store = try NotifiedEventStore.inMemory(now: { clock.now })
    }

    func testMarkIfNewIsTrueOnceThenFalse() async {
        let first = await store.markIfNew(id: "tx.abc", topic: .transactions)
        let second = await store.markIfNew(id: "tx.abc", topic: .transactions)
        let other = await store.markIfNew(id: "tx.def", topic: .transactions)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        XCTAssertTrue(other)
    }

    /// A database that cannot record (here: the table was never migrated)
    /// still admits an event once, but not again on the next rescan.
    func testMarkIfNewOnFailingDatabaseAdmitsEachIdOncePerProcess() async throws {
        let broken = NotifiedEventStore(connection: try Connection(.inMemory))

        let first = await broken.markIfNew(id: "tx.abc", topic: .transactions)
        let repeated = await broken.markIfNew(id: "tx.abc", topic: .transactions)
        let other = await broken.markIfNew(id: "tx.def", topic: .transactions)

        XCTAssertTrue(first)
        XCTAssertFalse(repeated)
        XCTAssertTrue(other)
    }

    /// `unmark` re-arms an id admitted without a record too, so a caller that
    /// posts one id repeatedly (CrowdNode's result) is not refused for good
    /// while the database is failing.
    func testUnmarkOnFailingDatabaseReadmitsTheId() async throws {
        let broken = NotifiedEventStore(connection: try Connection(.inMemory))

        _ = await broken.markIfNew(id: "crowdnode.result", topic: .crowdnode)
        await broken.unmark(id: "crowdnode.result")
        let again = await broken.markIfNew(id: "crowdnode.result", topic: .crowdnode)

        XCTAssertTrue(again)
    }

    func testMarkIfNewDedupsById_TopicDoesNotDisambiguate() async {
        // The id is the dedup key on its own — the same event surfacing via
        // another topic-tagged path must still be dropped.
        _ = await store.markIfNew(id: "event.1", topic: .transactions)
        let again = await store.markIfNew(id: "event.1", topic: .crowdnode)

        XCTAssertFalse(again)
    }

    func testUnseenCountCountsUnseenAcrossTopics() async {
        _ = await store.markIfNew(id: "tx.1", topic: .transactions)
        _ = await store.markIfNew(id: "tx.2", topic: .transactions)
        _ = await store.markIfNew(id: "cn.1", topic: .crowdnode)

        var count = await store.unseenCount()
        XCTAssertEqual(count, 3)

        await store.markAllSeen(topic: .transactions)

        count = await store.unseenCount()
        XCTAssertEqual(count, 1)
    }

    func testMarkAllSeenAffectsOnlyGivenTopicAndIsIdempotent() async {
        _ = await store.markIfNew(id: "tx.1", topic: .transactions)
        _ = await store.markIfNew(id: "cn.1", topic: .crowdnode)

        await store.markAllSeen(topic: .crowdnode)
        await store.markAllSeen(topic: .crowdnode)

        let count = await store.unseenCount()
        XCTAssertEqual(count, 1)
    }

    func testMarkAllSeenWithoutTopicClearsEveryTopic() async {
        _ = await store.markIfNew(id: "tx.1", topic: .transactions)
        _ = await store.markIfNew(id: "cn.1", topic: .crowdnode)
        _ = await store.markIfNew(id: "swap.1", topic: .swap)

        await store.markAllSeen()

        let count = await store.unseenCount()
        XCTAssertEqual(count, 0)
        // Seen is not forgotten: the ids stay recorded for dedup.
        let again = await store.markIfNew(id: "cn.1", topic: .crowdnode)
        XCTAssertFalse(again)
    }

    func testConsumeRecordsSeenAndDedups() async {
        await store.consume(id: "tx.watched", topic: .transactions)

        // Consumed events never count toward the badge...
        let unseen = await store.unseenCount()
        XCTAssertEqual(unseen, 0)
        // ...and can never be notified afterwards.
        let marked = await store.markIfNew(id: "tx.watched", topic: .transactions)
        XCTAssertFalse(marked)
    }

    func testConsumeLeavesAnAlreadyRecordedEventUntouched() async {
        _ = await store.markIfNew(id: "tx.posted", topic: .transactions)

        await store.consume(id: "tx.posted", topic: .transactions)

        // The posted event stays unseen — its seen state is the
        // lifecycle's to clear, not consume's.
        let unseen = await store.unseenCount()
        XCTAssertEqual(unseen, 1)
    }

    func testUnmarkRemovesRecordSoMarkIfNewSucceedsAgain() async {
        _ = await store.markIfNew(id: "tx.failed-post", topic: .transactions)

        await store.unmark(id: "tx.failed-post")

        // The row is gone: no badge weight, and the id counts as new again.
        let unseen = await store.unseenCount()
        XCTAssertEqual(unseen, 0)
        let marked = await store.markIfNew(id: "tx.failed-post", topic: .transactions)
        XCTAssertTrue(marked)
    }

    func testUnmarkOfAbsentIdIsNoOp() async {
        _ = await store.markIfNew(id: "tx.kept", topic: .transactions)

        await store.unmark(id: "tx.never-recorded")

        // Nothing else was touched.
        let unseen = await store.unseenCount()
        XCTAssertEqual(unseen, 1)
        let markedAgain = await store.markIfNew(id: "tx.kept", topic: .transactions)
        XCTAssertFalse(markedAgain)
    }

    func testPruneRemovesRowsOlderThanThirtyDays() async {
        _ = await store.markIfNew(id: "tx.old", topic: .transactions)

        clock.advance(days: 31)
        // Prune runs opportunistically on markAllSeen.
        await store.markAllSeen(topic: .transactions)

        let unseen = await store.unseenCount()
        XCTAssertEqual(unseen, 0)
        // The row is gone entirely, so the id counts as new again.
        let markedAgain = await store.markIfNew(id: "tx.old", topic: .transactions)
        XCTAssertTrue(markedAgain)
    }

    /// A database that failed and then RECOVERED inside the same process must
    /// not re-admit what it already let through. The banner went out on the
    /// failing write; the insert that now succeeds is the missing record, not
    /// a second event.
    func testAnIdAdmittedWhileTheDatabaseWasBrokenIsNotAdmittedAgainOnRecovery() async throws {
        let db = try Connection(.inMemory)
        let recovering = NotifiedEventStore(connection: db)

        // No table yet: the write fails and the id is admitted once.
        let whileBroken = await recovering.markIfNew(id: "tx.abc", topic: .transactions)
        let whileStillBroken = await recovering.markIfNew(id: "tx.abc", topic: .transactions)

        try AddNotifiedEventsTable().migrateDatabase(db)
        let afterRecovery = await recovering.markIfNew(id: "tx.abc", topic: .transactions)
        // And the record is there now, so the next scan is deduped by the row.
        let afterRecord = await recovering.markIfNew(id: "tx.abc", topic: .transactions)
        // An id the broken run never saw is still a genuine first sighting.
        let fresh = await recovering.markIfNew(id: "tx.def", topic: .transactions)

        XCTAssertTrue(whileBroken)
        XCTAssertFalse(whileStillBroken)
        XCTAssertFalse(afterRecovery)
        XCTAssertFalse(afterRecord)
        XCTAssertTrue(fresh)
    }

    /// `unmark` re-arms an id on BOTH paths, so a recovered database does not
    /// refuse the re-post it was unmarked for.
    func testUnmarkReArmsAnIdAdmittedWhileTheDatabaseWasBroken() async throws {
        let db = try Connection(.inMemory)
        let recovering = NotifiedEventStore(connection: db)
        _ = await recovering.markIfNew(id: "crowdnode.result", topic: .transactions)

        try AddNotifiedEventsTable().migrateDatabase(db)
        await recovering.unmark(id: "crowdnode.result")
        let afterUnmark = await recovering.markIfNew(id: "crowdnode.result", topic: .transactions)

        XCTAssertTrue(afterUnmark)
    }

    func testPruneKeepsRowsWithinThirtyDays() async {
        _ = await store.markIfNew(id: "tx.recent", topic: .transactions)

        clock.advance(days: 29)
        await store.markAllSeen(topic: .transactions)

        // Still recorded: seen (count 0) but not pruned, so still deduped.
        let unseen = await store.unseenCount()
        XCTAssertEqual(unseen, 0)
        let markedAgain = await store.markIfNew(id: "tx.recent", topic: .transactions)
        XCTAssertFalse(markedAgain)
    }
}
