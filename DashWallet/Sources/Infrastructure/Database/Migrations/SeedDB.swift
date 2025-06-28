import Foundation
import SQLite
import SQLiteMigrationManager

struct SeedDB: Migration {
    var version: Int64 = 20250418145536

    func migrateDatabase(_ db: Connection) throws { }
}
