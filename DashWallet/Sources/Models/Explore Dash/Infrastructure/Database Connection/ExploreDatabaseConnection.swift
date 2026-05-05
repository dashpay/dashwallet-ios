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
        print("🎯 ExploreDatabaseConnection: Adding test merchants...")

        guard let db = self.db else {
            print("🎯 ExploreDatabaseConnection: Database not ready yet")
            return
        }

        addPiggyCardsTestMerchants(db: db)
    }

    // Matches Android PiggyCardsTestMerchants data
    private let piggyCardsTestMerchants: [(
        merchantId: String, name: String, sourceId: String,
        merchantSavings: Int, merchantDenomType: String,
        providerSavings: Int, providerDenomType: String,
        logo: String, website: String,
        territory: String?, city: String?
    )] = [
        (
            "2e393eee-4508-47fe-954d-66209333fc96",
            "Piggy Cards Test Merchant",
            "177", -250, "Fixed", 100, "fixed",
            "https://piggy.cards/image/catalog/piggycards/logo2023_mobile.png",
            "https://piggy.cards", "MA", "Boston"
        ),
        (
            "2e393fff-4508-47fe-954d-66209333fc96",
            "Piggy Cards Flexible Test Merchant",
            "177", -250, "min-max", -250, "min-max",
            "https://piggy.cards/image/catalog/piggycards/logo2023_mobile.png",
            "https://piggy.cards", "MA", "Boston"
        ),
        (
            "2e393aaa-4508-47fe-954d-66209333fc96",
            "Home Depot [Flexible]",
            "74", 100, "min-max", -50, "min-max",
            "https://piggy.cards/image/catalog/piggycards/Home_Depot_Copy.jpg",
            "https://www.homedepot.com", nil, nil
        ),
        (
            "2e393ddd-4508-47fe-954d-66209333fc96",
            "Apple [Flexible]",
            "13", 100, "min-max", 100, "min-max",
            "https://piggy.cards/image/catalog/incenti/8aaa3d5d-logo.png",
            "https://www.apple.com", nil, nil
        ),
        (
            "2e393ccc-4508-47fe-954d-66209333fc96",
            "Dominos [Flexible]",
            "45", 100, "min-max", 150, "min-max",
            "https://piggy.cards/image/catalog/incenti/68ea431c-logo.png",
            "https://www.dominos.com", nil, nil
        ),
    ]

    private func addPiggyCardsTestMerchants(db: Connection) {
        do {
            let allIds = piggyCardsTestMerchants.map { "'\($0.merchantId)'" }.joined(separator: ", ")

            try db.transaction {
                // Drop FTS triggers to allow merchant table modifications
                try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_AFTER_INSERT")
                try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_AFTER_UPDATE")
                try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_BEFORE_UPDATE")
                try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_BEFORE_DELETE")

                // Delete existing test merchants (matches Android delete+re-insert pattern)
                try db.run("DELETE FROM gift_card_providers WHERE merchantId IN (\(allIds))")
                try db.run("DELETE FROM merchant WHERE merchantId IN (\(allIds))")

                // Insert all test merchants
                for m in piggyCardsTestMerchants {
                    let territory = "'\(m.territory ?? "")'"
                    let city = "'\(m.city ?? "")'"

                    try db.run("""
                        INSERT INTO merchant (
                            merchantId, name, source, sourceId, logoLocation, active, paymentMethod,
                            savingsPercentage, denominationsType, type, redeemType, territory, city,
                            website, addDate, updateDate
                        ) VALUES (
                            '\(m.merchantId)', '\(m.name)', 'PiggyCards', '\(m.sourceId)',
                            '\(m.logo)', 1, 'gift card', \(m.merchantSavings),
                            '\(m.merchantDenomType)', 'online', 'online',
                            \(territory), \(city), '\(m.website)',
                            datetime('now'), datetime('now')
                        )
                    """)

                    let rowId = db.lastInsertRowid

                    try db.run("""
                        INSERT INTO gift_card_providers (
                            merchantId, provider, sourceId, savingsPercentage,
                            denominationsType, active, redeemType
                        ) VALUES (
                            '\(m.merchantId)', 'PiggyCards', '\(m.sourceId)',
                            \(m.providerSavings), '\(m.providerDenomType)', 1, 'online'
                        )
                    """)

                    try db.run("INSERT INTO merchant_fts(docid, name) VALUES (\(rowId), '\(m.name)')")
                }

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
            }

            print("✅ PiggyCards test merchants added successfully (\(piggyCardsTestMerchants.count) merchants)")
        } catch {
            print("🎯 Error adding PiggyCards test merchants: \(error)")
        }
    }
    #endif
}
