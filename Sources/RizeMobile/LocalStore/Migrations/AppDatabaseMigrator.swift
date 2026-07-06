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
            try db.create(table: ActivityEventRecord.databaseTableName) { t in
                t.column("eventId", .text).primaryKey()
                t.column("deviceId", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime).notNull()
                t.column("appBundleId", .text)
                t.column("categoryId", .text)
                t.column("projectId", .text)
                t.column("deleted", .boolean).notNull().defaults(to: false)
                t.column("insertedAt", .datetime).notNull()
                t.column("syncedAt", .datetime)
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

            try db.create(table: FocusSessionRecord.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("deviceId", .text).notNull()
                t.column("projectId", .text)
                t.column("kind", .text).notNull()
                t.column("plannedDurationS", .integer)
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("status", .text).notNull()
                t.column("note", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("syncedAt", .datetime)
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

        return migrator
    }
}
