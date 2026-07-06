import Foundation
import GRDB

/// Errors surfaced by `GRDBLocalStore`.
public enum LocalStoreError: Error, Equatable {
    case sessionNotFound(UUID)
}

/// GRDB-backed implementation of `LocalStoring`.
///
/// All reads/writes go through GRDB's async `read`/`write` on the underlying
/// `DatabaseWriter`, so each call is a single serialized database
/// transaction — there is no interleaving of a start/stop/edit with a
/// concurrent sync-batch fetch.
public final class GRDBLocalStore: LocalStoring {
    private let database: AppDatabase
    private let deviceId: String
    private let clock: Clock
    private let uuidGenerator: UUIDv7Generator
    private let calendar: Calendar

    public init(
        database: AppDatabase,
        deviceId: String,
        clock: Clock = SystemClock(),
        uuidGenerator: UUIDv7Generator? = nil,
        calendar: Calendar = .current
    ) {
        self.database = database
        self.deviceId = deviceId
        self.clock = clock
        self.uuidGenerator = uuidGenerator ?? UUIDv7Generator(clock: clock)
        self.calendar = calendar
    }

    // MARK: Tier C — manual timer / focus sessions

    public func startSession(
        kind: FocusSessionKind,
        projectId: UUID?,
        plannedDurationS: Int?,
        note: String?
    ) async throws -> FocusSessionRecord {
        let now = clock.now()
        let session = FocusSessionRecord(
            id: uuidGenerator.next(),
            deviceId: deviceId,
            projectId: projectId,
            kind: kind,
            plannedDurationS: plannedDurationS,
            startedAt: now,
            endedAt: nil,
            status: .running,
            note: note,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            syncedAt: nil
        )
        try await database.dbWriter.write { db in
            try session.insert(db)
        }
        return session
    }

    public func stopSession(id: UUID, status: FocusSessionStatus) async throws -> FocusSessionRecord {
        let now = clock.now()
        return try await database.dbWriter.write { db in
            guard var session = try FocusSessionRecord.fetchOne(db, key: id.uuidString) else {
                throw LocalStoreError.sessionNotFound(id)
            }
            session.endedAt = now
            session.status = status
            session.updatedAt = now
            session.syncedAt = nil
            try session.update(db)
            return session
        }
    }

    public func editSession(id: UUID, projectId: UUID??, note: String??) async throws -> FocusSessionRecord {
        let now = clock.now()
        return try await database.dbWriter.write { db in
            guard var session = try FocusSessionRecord.fetchOne(db, key: id.uuidString) else {
                throw LocalStoreError.sessionNotFound(id)
            }
            if let projectId {
                session.projectId = projectId
            }
            if let note {
                session.note = note
            }
            session.updatedAt = now
            session.syncedAt = nil
            try session.update(db)
            return session
        }
    }

    public func deleteSession(id: UUID) async throws -> FocusSessionRecord {
        let now = clock.now()
        return try await database.dbWriter.write { db in
            guard var session = try FocusSessionRecord.fetchOne(db, key: id.uuidString) else {
                throw LocalStoreError.sessionNotFound(id)
            }
            session.deletedAt = now
            session.updatedAt = now
            session.syncedAt = nil
            try session.update(db)
            return session
        }
    }

    // MARK: Tier B — approximate usage events

    @discardableResult
    public func recordApproximateEvent(
        startedAt: Date,
        endedAt: Date,
        appBundleId: String?,
        categoryId: UUID?,
        projectId: UUID?
    ) async throws -> ActivityEventRecord {
        let event = ActivityEventRecord(
            eventId: uuidGenerator.next(),
            deviceId: deviceId,
            startedAt: startedAt,
            endedAt: endedAt,
            appBundleId: appBundleId,
            categoryId: categoryId,
            projectId: projectId,
            deleted: false,
            insertedAt: clock.now(),
            syncedAt: nil
        )
        try await database.dbWriter.write { db in
            try event.insert(db)
        }
        return event
    }

    // MARK: Fetching

    public func fetchTodayData() async throws -> TodayData {
        let now = clock.now()
        let dayInterval = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 0)

        return try await database.dbWriter.read { db in
            let events = try ActivityEventRecord
                .filter(Column("deleted") == false)
                .filter(Column("startedAt") >= dayInterval.start && Column("startedAt") < dayInterval.end)
                .order(Column("startedAt"))
                .fetchAll(db)

            let sessions = try FocusSessionRecord
                .filter(Column("deletedAt") == nil)
                .filter(Column("startedAt") >= dayInterval.start && Column("startedAt") < dayInterval.end)
                .order(Column("startedAt"))
                .fetchAll(db)

            return TodayData(events: events, sessions: sessions)
        }
    }

    public func fetchActiveRunningSession() async throws -> FocusSessionRecord? {
        try await database.dbWriter.read { db in
            try FocusSessionRecord
                .filter(Column("status") == FocusSessionStatus.running.rawValue)
                .filter(Column("deletedAt") == nil)
                .order(Column("startedAt").desc)
                .fetchOne(db)
        }
    }

    public func fetchUnsyncedBatch(limit: Int) async throws -> UnsyncedBatch {
        precondition(limit > 0, "limit must be positive")

        return try await database.dbWriter.read { db in
            let events = try ActivityEventRecord
                .filter(Column("syncedAt") == nil)
                .order(Column("startedAt"))
                .limit(limit)
                .fetchAll(db)

            let remaining = limit - events.count
            let sessions: [FocusSessionRecord] = remaining > 0
                ? try FocusSessionRecord
                .filter(Column("syncedAt") == nil)
                .order(Column("startedAt"))
                .limit(remaining)
                .fetchAll(db)
                : []

            return UnsyncedBatch(events: events, sessions: sessions)
        }
    }

    public func markSynced(events: [SyncedEventSnapshot], sessions: [SyncedSessionSnapshot]) async throws {
        guard !events.isEmpty || !sessions.isEmpty else { return }
        let now = clock.now()

        try await database.dbWriter.write { db in
            for event in events {
                try db.execute(
                    sql: """
                    UPDATE \(ActivityEventRecord.databaseTableName)
                    SET syncedAt = ?
                    WHERE eventId = ? AND insertedAt = ?
                    """,
                    arguments: [now, event.eventId.uuidString, event.insertedAt]
                )
            }
            for session in sessions {
                try db.execute(
                    sql: """
                    UPDATE \(FocusSessionRecord.databaseTableName)
                    SET syncedAt = ?
                    WHERE id = ? AND updatedAt = ?
                    """,
                    arguments: [now, session.id.uuidString, session.updatedAt]
                )
            }
        }
    }

    // MARK: Applying pulled changes

    public func applyEventChanges(upserts: [ActivityEventRecord], tombstoneIds: [UUID]) async throws {
        guard !upserts.isEmpty || !tombstoneIds.isEmpty else { return }
        let now = clock.now()

        try await database.dbWriter.write { db in
            for var upsert in upserts {
                upsert.syncedAt = now
                try upsert.save(db)
            }
            for tombstoneId in tombstoneIds {
                try db.execute(
                    sql: """
                    UPDATE \(ActivityEventRecord.databaseTableName)
                    SET deleted = 1, syncedAt = ?
                    WHERE eventId = ?
                    """,
                    arguments: [now, tombstoneId.uuidString]
                )
            }
        }
    }

    public func applySessionChanges(upserts: [FocusSessionRecord], tombstoneIds: [UUID]) async throws {
        guard !upserts.isEmpty || !tombstoneIds.isEmpty else { return }
        let now = clock.now()

        try await database.dbWriter.write { db in
            for var upsert in upserts {
                let existing = try FocusSessionRecord.fetchOne(db, key: upsert.id.uuidString)
                // LWW: only apply the incoming row if it is not older than
                // what's already stored locally. Ties favor the server, which
                // has already resolved LWW authoritatively.
                if let existing, existing.updatedAt > upsert.updatedAt {
                    continue
                }
                upsert.syncedAt = now
                try upsert.save(db)
            }
            for tombstoneId in tombstoneIds {
                guard let existing = try FocusSessionRecord.fetchOne(db, key: tombstoneId.uuidString) else {
                    continue
                }
                if existing.deletedAt != nil {
                    continue
                }
                try db.execute(
                    sql: """
                    UPDATE \(FocusSessionRecord.databaseTableName)
                    SET deletedAt = ?, updatedAt = ?, syncedAt = ?
                    WHERE id = ?
                    """,
                    arguments: [now, now, now, tombstoneId.uuidString]
                )
            }
        }
    }

    // MARK: Logout

    public func wipeAllData() async throws {
        try await database.dbWriter.write { db in
            try db.execute(sql: "DELETE FROM \(ActivityEventRecord.databaseTableName)")
            try db.execute(sql: "DELETE FROM \(FocusSessionRecord.databaseTableName)")
        }
    }
}
