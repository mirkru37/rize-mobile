import Foundation
import GRDB

/// A Tier B (approximate) usage event, mirroring the subset of the backend's
/// `activity_events` table (see [[database-schema]]) that mobile populates.
///
/// Per [[architecture-mobile.md]] §2, Tier B events originate from the
/// `DeviceActivityMonitor` extension's 5-minute threshold callbacks and are
/// always `precision: approximate`, `type: mobile_usage`, `source: mobile` —
/// those three fields are therefore fixed constants rather than stored
/// variability, but are kept as columns so a locally stored row already
/// matches the wire shape defined in [[sync-protocol]].
///
/// `eventId` is a client-generated UUIDv7 (see `UUIDv7Generator`), matching
/// the append-only/immutable entity class in [[sync-protocol]] §Entity
/// Classes: idempotency is `(user_id, event_id, started_at)` server-side, and
/// a "deletion" is a tombstone (`deleted = true`) rather than a hard delete.
public struct ActivityEventRecord: Codable, Equatable, Sendable {
    public static let type = "mobile_usage"
    public static let source = "mobile"
    public static let precision = "approximate"

    public var eventId: UUID
    public var deviceId: String
    public var startedAt: Date
    public var endedAt: Date
    public var appBundleId: String?
    public var categoryId: UUID?
    public var projectId: UUID?
    /// Tombstone flag, per [[database-schema]]'s convention for
    /// `activity_events` (a plain boolean rather than `deleted_at`, since
    /// this table is append-only and never otherwise mutated).
    public var deleted: Bool
    public var insertedAt: Date
    /// Sync bookkeeping: `nil` means the row is pending (not yet pushed);
    /// non-nil records when the row was last confirmed synced.
    public var syncedAt: Date?

    public var durationS: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt)))
    }

    public init(
        eventId: UUID,
        deviceId: String,
        startedAt: Date,
        endedAt: Date,
        appBundleId: String? = nil,
        categoryId: UUID? = nil,
        projectId: UUID? = nil,
        deleted: Bool = false,
        insertedAt: Date,
        syncedAt: Date? = nil
    ) {
        self.eventId = eventId
        self.deviceId = deviceId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.appBundleId = appBundleId
        self.categoryId = categoryId
        self.projectId = projectId
        self.deleted = deleted
        self.insertedAt = insertedAt
        self.syncedAt = syncedAt
    }
}

/// `FetchableRecord`/`PersistableRecord` are implemented by hand (rather than
/// relying on GRDB's Codable synthesis, which stores `UUID` as a 16-byte
/// BLOB) so that id columns are stored as `TEXT` — matching the migration in
/// `AppDatabaseMigrator` and making rows directly inspectable/debuggable,
/// and consistent with the JSON string form ids take on the wire in
/// [[sync-protocol]].
extension ActivityEventRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "activityEvents"

    public init(row: Row) throws {
        guard let eventId = UUID(uuidString: row["eventId"]) else {
            throw DatabaseError(message: "invalid eventId in row")
        }
        self.eventId = eventId
        deviceId = row["deviceId"]
        startedAt = row["startedAt"]
        endedAt = row["endedAt"]
        appBundleId = row["appBundleId"]
        categoryId = (row["categoryId"] as String?).flatMap(UUID.init(uuidString:))
        projectId = (row["projectId"] as String?).flatMap(UUID.init(uuidString:))
        deleted = row["deleted"]
        insertedAt = row["insertedAt"]
        syncedAt = row["syncedAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["eventId"] = eventId.uuidString
        container["deviceId"] = deviceId
        container["startedAt"] = startedAt
        container["endedAt"] = endedAt
        container["appBundleId"] = appBundleId
        container["categoryId"] = categoryId?.uuidString
        container["projectId"] = projectId?.uuidString
        container["deleted"] = deleted
        container["insertedAt"] = insertedAt
        container["syncedAt"] = syncedAt
    }
}
