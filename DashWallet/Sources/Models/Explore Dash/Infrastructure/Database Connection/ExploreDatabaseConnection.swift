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
    private var db: Connection!

    init() {
        NotificationCenter.default.addObserver(forName: ExploreDatabaseSyncManager.databaseHasBeenUpdatedNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            try? self?.connect()
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
}
