//
//  Created by Pavel Tikhonenko
//  Copyright © 2022 Dash Core Group. All rights reserved.
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

// MARK: - ExploreDatabaseConnectionError

enum ExploreDatabaseConnectionError: Error {
    case fileNotFound
}

// MARK: - ExploreDatabaseConnection

let kExploreDashDatabaseName = "explore.db"

// MARK: - ExploreDatabaseConnection

class ExploreDatabaseConnection {
    var db: Connection!

    init() {
        NotificationCenter.default.addObserver(forName: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            try? self?.connect()

            // Add test merchant after database sync for TestFlight builds
            #if DEBUG || Testflight
            self?.addTestMerchantAfterSync()
            #endif
        }
    }
    
    static func hasOldMerchantIdSchema(at url: URL) -> Bool {
        do {
            let db = try Connection(url.path)
            // Query the sqlite_master table to get the schema
            let query = "SELECT sql FROM sqlite_master WHERE type='table' AND name='merchant'"
            
            if let row = try db.prepare(query).makeIterator().next(),
               let sql = row[0] as? String {
                // Check if merchantId is defined as INTEGER (old schema)
                // New schema should have it as TEXT
                return sql.contains("merchantId` INTEGER") || sql.contains("merchantId INTEGER")
            }
        } catch {
            // If we can't check, assume it might be old to be safe
            return true
        }
        return false
    }

    func connect() throws {
        db = nil

        guard let dbPath = dbPath() else {
            // No database found - this is expected if we're waiting for v3 download
            // Create an in-memory database to prevent crashes
            db = try Connection(.inMemory)
            return
        }

        do {
            db = try Connection(dbPath)

            // Add test merchant on initial connection for TestFlight builds
            #if DEBUG || Testflight
            // Use a small delay to ensure database is fully connected
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.insertTestMerchant()
            }
            #endif
        } catch {
            print(error)
            // Fallback to in-memory database if connection fails
            db = try Connection(.inMemory)
        }
    }

    private func dbPath() -> String? {
        let downloadedPath = FileManager.documentsDirectoryURL.appendingPathComponent(kExploreDashDatabaseName).path

        return FileManager.default.fileExists(atPath: downloadedPath) ? downloadedPath : nil
    }

    func execute<Item: RowDecodable>(query: QueryType) throws -> [Item] {
        guard db != nil else { return [] }
        
        do {
            let items = try db.prepare(query)

            var resultItems: [Item] = []

            for item in items {
                resultItems.append(Item(row: item))
            }

            return resultItems
        } catch {
            // If query fails (e.g., table doesn't exist in in-memory db), return empty array
            print("Database query failed: \(error)")
            return []
        }
    }

    func execute<Item: RowDecodable>(query: String) throws -> [Item] {
        guard db != nil else { return [] }

        do {
            return try db.prepareRowIterator(query).map { Item(row: $0) }
        } catch {
            // If query fails (e.g., table doesn't exist in in-memory db), return empty array
            print("Database query failed: \(error)")
            return []
        }
    }

    #if DEBUG || Testflight
    private func addTestMerchantAfterSync() {
        // Wait a bit to ensure database is fully ready after sync
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.insertTestMerchant()
        }
    }

    private func insertTestMerchant() {
        print("🎯 ExploreDatabaseConnection: Adding test merchant...")

        guard let db = self.db else {
            print("🎯 ExploreDatabaseConnection: Database not ready yet")
            return
        }

        // Add PiggyCards test merchant
        addPiggyCardsTestMerchant(db: db)
    }

    private func addPiggyCardsTestMerchant(db: Connection) {
        do {
            let testMerchantId = "2e393eee-4508-47fe-954d-66209333fc96"

            // Check if merchant already exists
            let checkQuery = "SELECT COUNT(*) FROM merchant WHERE merchantId = '\(testMerchantId)'"
            let count = try db.scalar(checkQuery) as? Int64 ?? 0

            if count > 0 {
                print("🎯 PiggyCards test merchant already exists, skipping")
                return
            }

            print("🎯 Adding PiggyCards test merchant...")

            // Drop FTS triggers temporarily
            try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_AFTER_INSERT")
            try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_AFTER_UPDATE")
            try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_BEFORE_UPDATE")
            try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_BEFORE_DELETE")

            // Insert merchant with unique prefix
            try db.run("""
                INSERT INTO merchant (
                    merchantId, name, source, sourceId, logoLocation, active, paymentMethod,
                    savingsPercentage, denominationsType, type, redeemType, territory, city,
                    website, addDate, updateDate
                ) VALUES (
                    '2e393eee-4508-47fe-954d-66209333fc96',
                    'Piggy Cards Test Merchant',
                    'PiggyCards',
                    '177',
                    'https://piggy.cards/image/catalog/piggycards/logo2023_mobile.png',
                    1,
                    'gift card',
                    1000,
                    'Fixed',
                    'online',
                    'online',
                    'MA',
                    'Boston',
                    'https://piggy.cards',
                    datetime('now'),
                    datetime('now')
                )
            """)

            let insertedRowId = db.lastInsertRowid

            // Insert gift_card_providers record
            try db.run("""
                INSERT INTO gift_card_providers (
                    merchantId, provider, sourceId, savingsPercentage,
                    denominationsType, active, redeemType
                ) VALUES (
                    '2e393eee-4508-47fe-954d-66209333fc96',
                    'PiggyCards',
                    '177',
                    10,
                    'fixed',
                    1,
                    'online'
                )
            """)

            // Update FTS index
            try db.run("""
                INSERT INTO merchant_fts(docid, name)
                VALUES (\(insertedRowId), 'Piggy Cards Test Merchant')
            """)

            // Recreate FTS triggers
            try db.run("""
                CREATE TRIGGER room_fts_content_sync_merchant_fts_BEFORE_UPDATE
                BEFORE UPDATE ON merchant BEGIN
                    DELETE FROM merchant_fts WHERE docid=OLD.rowid;
                END
            """)

            try db.run("""
                CREATE TRIGGER room_fts_content_sync_merchant_fts_BEFORE_DELETE
                BEFORE DELETE ON merchant BEGIN
                    DELETE FROM merchant_fts WHERE docid=OLD.rowid;
                END
            """)

            try db.run("""
                CREATE TRIGGER room_fts_content_sync_merchant_fts_AFTER_UPDATE
                AFTER UPDATE ON merchant BEGIN
                    INSERT INTO merchant_fts(docid, name) VALUES (NEW.rowid, NEW.name);
                END
            """)

            try db.run("""
                CREATE TRIGGER room_fts_content_sync_merchant_fts_AFTER_INSERT
                AFTER INSERT ON merchant BEGIN
                    INSERT INTO merchant_fts(docid, name) VALUES (NEW.rowid, NEW.name);
                END
            """)

            print("✅ PiggyCards test merchant added successfully")

        } catch {
            print("🎯 Error adding PiggyCards test merchant: \(error)")
        }
    }
    #endif
}
