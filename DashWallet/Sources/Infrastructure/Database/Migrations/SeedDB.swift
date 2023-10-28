import Foundation
import SQLite
import SQLiteMigrationManager

struct SeedDB: Migration {
    var version: Int64 = 20231023152234

    func migrateDatabase(_ db: Connection) throws { }
}
