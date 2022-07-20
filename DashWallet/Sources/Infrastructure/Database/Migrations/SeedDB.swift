import Foundation
import SQLiteMigrationManager
import SQLite

struct SeedDB: Migration {
  var version: Int64 = 20220713105051

  func migrateDatabase(_ db: Connection) throws {
  }
}
