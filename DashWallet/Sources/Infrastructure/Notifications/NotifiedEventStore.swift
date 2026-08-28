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
    /// Events recorded but not yet seen in the app, across all topics —
    /// the number the app badge shows.
    func unseenCount() async -> Int
    /// Marks every event of `topic` seen; opportunistically prunes rows
    /// older than `NotifiedEventStore.retentionInterval`.
    func markAllSeen(topic: NotificationTopic) async
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
            // `seen_at` is left at its NULL default — the event is unseen.
            try connection.run(S.table.insert(
                or: .ignore,
                S.colId <- id,
                S.colTopic <- topic.rawValue,
                S.colCreatedAt <- epochSeconds(now())))
            // `insert(or: .ignore)` leaves an existing row untouched;
            // `changes == 0` is the "already notified" signal.
            return connection.changes > 0
        } catch {
            DWLogger.log("NotifiedEventStore: markIfNew(\(id)) failed: \(error)")
            // Fail open: nothing was recorded, so dedup for this id is lost —
            // but a broken database must not silently swallow notifications.
            return true
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
