import GRDB
import XCTest
@testable import RizeMobile

final class AppDatabaseMigrationTests: XCTestCase {
    func testMigratorCreatesExpectedTables() throws {
        let database = try AppDatabase.inMemory()

        let tableNames = try database.dbWriter.read { db in
            try Set(String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }

        XCTAssertTrue(tableNames.contains(ActivityEventRecord.databaseTableName))
        XCTAssertTrue(tableNames.contains(FocusSessionRecord.databaseTableName))
    }

    func testMigrationsAreIdempotentWhenReappliedToTheSameDatabase() throws {
        let dbWriter = try DatabaseQueue()
        _ = try AppDatabase(dbWriter: dbWriter)

        // Re-running the migrator against a database that already has the
        // migrations applied must be a no-op, not an error.
        XCTAssertNoThrow(try AppDatabaseMigrator.makeMigrator().migrate(dbWriter))
    }

    func testActivityEventsPrimaryKeyPreventsDuplicateEventIds() throws {
        let database = try AppDatabase.inMemory()
        let eventId = UUID()
        let now = Date()

        let event = ActivityEventRecord(
            eventId: eventId,
            deviceId: "device-1",
            startedAt: now,
            endedAt: now.addingTimeInterval(300),
            insertedAt: now
        )

        try database.dbWriter.write { db in
            try event.insert(db)
        }

        try database.dbWriter.write { db in
            XCTAssertThrowsError(try event.insert(db))
        }
    }
}
