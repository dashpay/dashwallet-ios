//
//  Created by Andrei Ashikhmin
//  Copyright © 2025 Dash Core Group. All rights reserved.
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

// IMPORTANT: This migration is for TESTING ONLY and must be removed before production release
// It adds a test merchant for PiggyCards integration testing in TestFlight builds
struct AddPiggyCardsTestMerchant: Migration {
    var version: Int64 = 20251121100000  // Using current timestamp

    func migrateDatabase(_ db: Connection) throws {
        // Check if we're in a test/debug configuration
        #if DEBUG || TESTFLIGHT

        // First, check if the test merchant already exists to avoid duplicates
        let merchantTable = Table("merchant")
        let merchantId = Expression<String>("merchantId")
        let testMerchantId = "2e393eee-4508-47fe-954d-66209333fc96"

        let existingMerchant = try db.pluck(merchantTable.filter(merchantId == testMerchantId))

        if existingMerchant == nil {
            // Temporarily drop FTS triggers to avoid "unsafe use of virtual table" error
            try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_AFTER_INSERT")
            try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_AFTER_UPDATE")
            try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_BEFORE_UPDATE")
            try db.run("DROP TRIGGER IF EXISTS room_fts_content_sync_merchant_fts_BEFORE_DELETE")

            // Insert the test merchant
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

            // Get the rowid of the inserted merchant for FTS
            let insertedRowId = db.lastInsertRowid

            // Insert corresponding gift_card_providers record
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

            // Manually update FTS index
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

            print("✅ PiggyCards test merchant added successfully for testing")
        } else {
            print("ℹ️ PiggyCards test merchant already exists, skipping insertion")
        }

        #else
        // In production builds, this migration does nothing
        print("ℹ️ Skipping test merchant insertion in production build")
        #endif
    }
}