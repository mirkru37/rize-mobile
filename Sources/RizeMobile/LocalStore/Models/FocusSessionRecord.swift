import Foundation
import GRDB

/// The three session kinds a user can start manually, per [[database-schema]]
/// `focus_sessions.kind`.
public enum FocusSessionKind: String, Codable, Sendable, CaseIterable {
    case focus
    case breakTime = "break"
    case meeting
}

/// Lifecycle status of a session, per [[database-schema]] `focus_sessions.status`.
public enum FocusSessionStatus: String, Codable, Sendable, CaseIterable {
    case running
    case completed
    case abandoned
}

/// A Tier C (exact, synced) manual timer / focus session, mirroring the
/// backend's `focus_sessions` table (see [[database-schema]]).
///
/// Per [[architecture-mobile.md]] §2, Tier C sessions are started and stopped
/// explicitly by the user, so their durations are exact by construction and
/// carry no precision caveat. Per [[sync-protocol]] §Entity Classes,
/// `focus_sessions` is a **mutable, last-write-wins** entity: `id` is a
/// client-generated UUIDv7, `updatedAt` is the LWW comparison key, and a
/// tombstone is `deletedAt` being set rather than a hard delete.
public struct FocusSessionRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var deviceId: String
    public var projectId: UUID?
    public var kind: FocusSessionKind
    public var plannedDurationS: Int?
    public var startedAt: Date
    public var endedAt: Date?
    public var status: FocusSessionStatus
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date
    /// Tombstone timestamp, per [[database-schema]]'s soft-delete convention
    /// for mutable entities.
    public var deletedAt: Date?
    /// Sync bookkeeping: `nil` means the row is pending (not yet pushed);
    /// non-nil records when this version of the row was last confirmed synced.
    public var syncedAt: Date?

    public init(
        id: UUID,
        deviceId: String,
        projectId: UUID? = nil,
        kind: FocusSessionKind,
        plannedDurationS: Int? = nil,
        startedAt: Date,
        endedAt: Date? = nil,
        status: FocusSessionStatus,
        note: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date? = nil,
        syncedAt: Date? = nil
    ) {
        self.id = id
        self.deviceId = deviceId
        self.projectId = projectId
        self.kind = kind
        self.plannedDurationS = plannedDurationS
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.syncedAt = syncedAt
    }
}

/// See `ActivityEventRecord`'s equivalent extension for why these are
/// implemented by hand: id columns are stored as `TEXT`, not GRDB's default
/// 16-byte BLOB encoding of `UUID`.
extension FocusSessionRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "focusSessions"

    public init(row: Row) throws {
        guard let id = UUID(uuidString: row["id"]) else {
            throw DatabaseError(message: "invalid id in row")
        }
        self.id = id
        deviceId = row["deviceId"]
        projectId = (row["projectId"] as String?).flatMap(UUID.init(uuidString:))
        kind = FocusSessionKind(rawValue: row["kind"]) ?? .focus
        plannedDurationS = row["plannedDurationS"]
        startedAt = row["startedAt"]
        endedAt = row["endedAt"]
        status = FocusSessionStatus(rawValue: row["status"]) ?? .running
        note = row["note"]
        createdAt = row["createdAt"]
        updatedAt = row["updatedAt"]
        deletedAt = row["deletedAt"]
        syncedAt = row["syncedAt"]
    }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id.uuidString
        container["deviceId"] = deviceId
        container["projectId"] = projectId?.uuidString
        container["kind"] = kind.rawValue
        container["plannedDurationS"] = plannedDurationS
        container["startedAt"] = startedAt
        container["endedAt"] = endedAt
        container["status"] = status.rawValue
        container["note"] = note
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
        container["deletedAt"] = deletedAt
        container["syncedAt"] = syncedAt
    }
}
