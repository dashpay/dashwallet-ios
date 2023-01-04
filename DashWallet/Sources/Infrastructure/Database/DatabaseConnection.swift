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
        print("SQLite: ", DatabaseConnection.storeURL().absoluteString)
        do {
            db = try Connection(DatabaseConnection.storeURL().absoluteString)
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

        guard let documentsURL = URL(string: docsDir) else {
            fatalError("could not get user documents directory URL")
        }

        return documentsURL.appendingPathComponent(kDatabaseName)
    }

    static func migrations() -> [Migration] {
        [SeedDB()]
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
