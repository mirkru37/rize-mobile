import Foundation
import GRDB

/// Builds the GRDB `DatabaseMigrator` for the on-device local store.
///
/// Each migration is additive and named so future schema changes can be
/// appended as new `registerMigration` calls without altering history, per
/// GRDB's standard migration model.
enum AppDatabaseMigrator {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_local_store") { db in
            try createActivityEvents(db)
            try createFocusSessions(db)
        }

        return migrator
    }

    private static func createActivityEvents(_ db: Database) throws {
        try db.create(table: ActivityEventRecord.databaseTableName) { table in
            table.column("eventId", .text).primaryKey()
            table.column("deviceId", .text).notNull()
            table.column("startedAt", .datetime).notNull()
            table.column("endedAt", .datetime).notNull()
            table.column("appBundleId", .text)
            table.column("categoryId", .text)
            table.column("projectId", .text)
            table.column("deleted", .boolean).notNull().defaults(to: false)
            table.column("insertedAt", .datetime).notNull()
            table.column("syncedAt", .datetime)
        }
        try db.create(
            index: "idx_activityEvents_startedAt",
            on: ActivityEventRecord.databaseTableName,
            columns: ["startedAt"]
        )
        try db.create(
            index: "idx_activityEvents_syncedAt",
            on: ActivityEventRecord.databaseTableName,
            columns: ["syncedAt"]
        )
    }

    private static func createFocusSessions(_ db: Database) throws {
        try db.create(table: FocusSessionRecord.databaseTableName) { table in
            table.column("id", .text).primaryKey()
            table.column("deviceId", .text).notNull()
            table.column("projectId", .text)
            table.column("kind", .text).notNull()
            table.column("plannedDurationS", .integer)
            table.column("startedAt", .datetime).notNull()
            table.column("endedAt", .datetime)
            table.column("status", .text).notNull()
            table.column("note", .text)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
            table.column("syncedAt", .datetime)
        }
        try db.create(
            index: "idx_focusSessions_startedAt",
            on: FocusSessionRecord.databaseTableName,
            columns: ["startedAt"]
        )
        try db.create(
            index: "idx_focusSessions_syncedAt",
            on: FocusSessionRecord.databaseTableName,
            columns: ["syncedAt"]
        )
    }
}
