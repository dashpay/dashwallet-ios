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
import SQLiteMigrationManager

private let kDatabaseName = "store.db"

// MARK: - DatabaseConnection

@objc
class DatabaseConnection: NSObject {
    var db: Connection!
    var migrationManager: SQLiteMigrationManager!

    override init() {
        let databaseURL = DatabaseConnection.storeURL()
        print("SQLite: ", databaseURL.path)
        do {
            db = try Connection(databaseURL.path)
            migrationManager = SQLiteMigrationManager(db: db,
                                                      migrations: DatabaseConnection.migrations(),
                                                      bundle: DatabaseConnection.migrationsBundle())
        } catch {
            print("DatabaseConnection", error)
        }

        super.init()
    }

    @objc
    func migrateIfNeeded() throws {
        guard let migrationManager else {
            throw NSError(domain: "DatabaseConnection", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The wallet database could not be opened."
            ])
        }

        if !migrationManager.hasMigrationsTable() {
            try migrationManager.createMigrationsTable()
        }

        if migrationManager.needsMigration() {
            try migrationManager.migrateDatabase()
        }
    }

    @objc static let shared = DatabaseConnection()
}

extension DatabaseConnection {

    static func storeURL() -> URL {
        let dirPaths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let docsDir = dirPaths[0] as String

        return URL(fileURLWithPath: docsDir, isDirectory: true)
            .appendingPathComponent(kDatabaseName)
    }

    static func migrations() -> [Migration] {
        return [
            SeedDB(),
            AddGiftCardsTable(),
            AddIconBitmapsTable(),
            AddProviderToGiftCardsTable(),
            AddRedeemUrlChallengeToGiftCardsTable(),
            AddSwapOrdersTable(),
            AddPlatformAddressActivityTables(),
            NormalizePlatformAddressActivityUnits()
        ]
    }

    static func migrationsBundle() -> Bundle {
        guard let bundleURL = Bundle.main.url(forResource: "Migrations", withExtension: "bundle") else {
            fatalError("could not find migrations bundle")
        }
        guard let bundle = Bundle(url: bundleURL) else {
            fatalError("could not load migrations bundle")
        }

        return bundle
    }
}
