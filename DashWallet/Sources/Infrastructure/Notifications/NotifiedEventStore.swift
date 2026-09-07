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

import Foundation
import SQLite
import SQLiteMigrationManager

// MARK: - NotifiedEventStoring

/// Persisted dedup and badge truth for posted notifications.
protocol NotifiedEventStoring: AnyObject {
    /// Records the event as notified. `false` means it was already recorded
    /// and the caller must not notify again.
    func markIfNew(id: String, topic: NotificationTopic) async -> Bool
    /// Records the event as notified AND already seen, without a post — for
    /// an event whose content the user was watching in the app when it
    /// occurred, so a later scan cannot notify it and the badge never counts
    /// it. An id that is already recorded is left untouched.
    func consume(id: String, topic: NotificationTopic) async
    /// Deletes the record for `id`, so a later `markIfNew` succeeds again —
    /// the dispatcher's rollback when handing the request to the
    /// notification center failed after the mark. An absent id is a no-op.
    func unmark(id: String) async
    /// Events recorded but not yet seen in the app, across all topics —
    /// the number the app badge shows.
    func unseenCount() async -> Int
    /// Marks every event of `topic` seen; opportunistically prunes rows
    /// older than `NotifiedEventStore.retentionInterval`.
    func markAllSeen(topic: NotificationTopic) async
    /// Marks every unseen event seen, across all topics — the store-side
    /// half of zeroing the app badge, so the next posted badge does not
    /// resurrect events the cleared badge already represented. Prunes like
    /// `markAllSeen(topic:)`.
    func markAllSeen() async
}

// MARK: - Schema

enum NotifiedEventSchema {
    static let table = Table("notified_events")

    static let colId = SQLite.Expression<String>("id")
    static let colTopic = SQLite.Expression<String>("topic")
    static let colCreatedAt = SQLite.Expression<Int64>("created_at")
    static let colSeenAt = SQLite.Expression<Int64?>("seen_at")
}

// MARK: - Migration

struct AddNotifiedEventsTable: Migration {
    var version: Int64 = 20260827100000

    func migrateDatabase(_ db: Connection) throws {
        typealias S = NotifiedEventSchema
        try db.run(S.table.create(ifNotExists: true) { t in
            t.column(S.colId, primaryKey: true)
            t.column(S.colTopic)
            t.column(S.colCreatedAt)
            t.column(S.colSeenAt)
        })
    }
}

// MARK: - NotifiedEventStore

/// SQLite-backed store over the app's shared `store.db` (or any injected
/// connection). An `actor`, so every database access is serialized on its
/// executor — the same pattern as `SwapOrdersDAOImpl`, and the table is tiny,
/// so synchronous SQLite on the actor's executor is cheap and race-free.
actor NotifiedEventStore: NotifiedEventStoring {
    /// Rows older than this are deleted: dedup for month-old events is no
    /// longer meaningful, and the table must not grow unbounded.
    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    private let connection: Connection
    private let now: () -> Date

    init(connection: Connection, now: @escaping () -> Date = Date.init) {
        self.connection = connection
        self.now = now
    }

    /// The production store, over the app's shared database. The
    /// `notified_events` table is created by the `AddNotifiedEventsTable`
    /// migration `DatabaseConnection.migrateIfNeeded()` runs at launch.
    static func onSharedDatabase() -> NotifiedEventStore {
        NotifiedEventStore(connection: DatabaseConnection.shared.db)
    }

    /// A store over a private in-memory database with the schema migrated —
    /// full isolation for tests.
    static func inMemory(now: @escaping () -> Date = Date.init) throws -> NotifiedEventStore {
        let db = try Connection(.inMemory)
        try AddNotifiedEventsTable().migrateDatabase(db)
        return NotifiedEventStore(connection: db, now: now)
    }

    // MARK: NotifiedEventStoring

    func markIfNew(id: String, topic: NotificationTopic) async -> Bool {
        typealias S = NotifiedEventSchema
        do {
            // Existence check, then a plain insert, inside one transaction.
            // NOT `insert(or: .ignore)` + `connection.changes`: `changes` is
            // `sqlite3_changes` on the app-wide shared connection, read
            // after `run` has released the connection queue, so any other
            // DAO's statement landing in between replaces the count — a
            // real insert could read as a duplicate (event suppressed for
            // good) and a duplicate as a real insert (posted twice). The
            // transaction holds the connection queue for both statements,
            // and this actor is the table's only writer, so the check
            // cannot go stale before the insert.
            var inserted = false
            try connection.transaction {
                let exists = try connection.scalar(S.table.filter(S.colId == id).count) > 0
                guard !exists else { return }
                // `seen_at` is left at its NULL default — the event is unseen.
                try connection.run(S.table.insert(
                    S.colId <- id,
                    S.colTopic <- topic.rawValue,
                    S.colCreatedAt <- epochSeconds(now())))
                inserted = true
            }
            return inserted
        } catch {
            DWLogger.log("NotifiedEventStore: markIfNew(\(id)) failed: \(error)")
            // Fail open: nothing was recorded, so dedup for this id is lost —
            // but a broken database must not silently swallow notifications.
            return true
        }
    }

    func consume(id: String, topic: NotificationTopic) async {
        typealias S = NotifiedEventSchema
        do {
            // `seen_at` is set up front — the event was on screen when it
            // happened. `insert(or: .ignore)` leaves an id that was posted
            // earlier untouched; its seen state is the lifecycle's to manage.
            let stamp = epochSeconds(now())
            try connection.run(S.table.insert(
                or: .ignore,
                S.colId <- id,
                S.colTopic <- topic.rawValue,
                S.colCreatedAt <- stamp,
                S.colSeenAt <- stamp))
        } catch {
            DWLogger.log("NotifiedEventStore: consume(\(id)) failed: \(error)")
        }
    }

    func unmark(id: String) async {
        typealias S = NotifiedEventSchema
        do {
            try connection.run(S.table.filter(S.colId == id).delete())
        } catch {
            DWLogger.log("NotifiedEventStore: unmark(\(id)) failed: \(error)")
        }
    }

    func unseenCount() async -> Int {
        typealias S = NotifiedEventSchema
        do {
            return try connection.scalar(S.table.filter(S.colSeenAt == nil).count)
        } catch {
            DWLogger.log("NotifiedEventStore: unseenCount failed: \(error)")
            return 0
        }
    }

    func markAllSeen(topic: NotificationTopic) async {
        typealias S = NotifiedEventSchema
        do {
            try connection.run(S.table
                .filter(S.colTopic == topic.rawValue && S.colSeenAt == nil)
                .update(S.colSeenAt <- epochSeconds(now())))
        } catch {
            DWLogger.log("NotifiedEventStore: markAllSeen(\(topic.rawValue)) failed: \(error)")
        }
        pruneExpired()
    }

    func markAllSeen() async {
        typealias S = NotifiedEventSchema
        do {
            try connection.run(S.table
                .filter(S.colSeenAt == nil)
                .update(S.colSeenAt <- epochSeconds(now())))
        } catch {
            DWLogger.log("NotifiedEventStore: markAllSeen failed: \(error)")
        }
        pruneExpired()
    }

    // MARK: Private

    /// Deletes rows older than `retentionInterval`, seen or not.
    private func pruneExpired() {
        typealias S = NotifiedEventSchema
        let cutoff = epochSeconds(now().addingTimeInterval(-Self.retentionInterval))
        do {
            try connection.run(S.table.filter(S.colCreatedAt < cutoff).delete())
        } catch {
            DWLogger.log("NotifiedEventStore: prune failed: \(error)")
        }
    }

    private func epochSeconds(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970)
    }
}
