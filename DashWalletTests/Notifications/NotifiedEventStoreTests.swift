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
