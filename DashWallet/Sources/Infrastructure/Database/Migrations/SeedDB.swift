import Foundation
import SQLite
import SQLiteMigrationManager

struct SeedDB: Migration {
    var version: Int64 = 20241130210940

    func migrateDatabase(_ db: Connection) throws { }
}
