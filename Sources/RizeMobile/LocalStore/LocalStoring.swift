import Foundation

/// A page of pending (unsynced) rows across both syncable entity types,
/// bounded to [[sync-protocol]]'s **500 items per push batch** limit,
/// counting `events.count + sessions.count` together.
public struct UnsyncedBatch: Equatable, Sendable {
    public var events: [ActivityEventRecord]
    public var sessions: [FocusSessionRecord]

    public var count: Int {
        events.count + sessions.count
    }

    public init(events: [ActivityEventRecord] = [], sessions: [FocusSessionRecord] = []) {
        self.events = events
        self.sessions = sessions
    }
}

/// Today's blended local data (Tier B events + Tier C sessions), for
/// dashboard display. Per [[architecture-mobile.md]] §6, callers combining
/// these must preserve provenance rather than merging them into a single
/// undifferentiated total.
public struct TodayData: Equatable, Sendable {
    public var events: [ActivityEventRecord]
    public var sessions: [FocusSessionRecord]

    public init(events: [ActivityEventRecord] = [], sessions: [FocusSessionRecord] = []) {
        self.events = events
        self.sessions = sessions
    }
}

/// The on-device local store's public API.
///
/// This is the seam between the main app / sync client and the concrete
/// GRDB-backed storage (`GRDBLocalStore`), so both can be exercised against
/// an in-memory database in tests, and so a future replacement store only
/// needs to conform to this protocol.
public protocol LocalStoring: Sendable {
    // MARK: Tier C — manual timer / focus sessions

    /// Starts a new session. The store mints its own client-generated
    /// UUIDv7 id via `UUIDv7Generator` — callers never supply one.
    func startSession(
        kind: FocusSessionKind,
        projectId: UUID?,
        plannedDurationS: Int?,
        note: String?
    ) async throws -> FocusSessionRecord

    /// Stops a running session, setting `endedAt` to now and `status` to the
    /// given terminal status (`completed` or `abandoned`).
    func stopSession(id: UUID, status: FocusSessionStatus) async throws -> FocusSessionRecord

    /// Edits a session's mutable fields. Bumps `updatedAt` to now so the
    /// change is picked up by the next unsynced-batch fetch, per
    /// [[sync-protocol]]'s last-write-wins strategy for `focus_sessions`.
    func editSession(id: UUID, projectId: UUID??, note: String??) async throws -> FocusSessionRecord

    /// Tombstones a session (`deletedAt` set to now) rather than a hard
    /// delete, per [[sync-protocol]]'s LWW tombstone rule.
    func deleteSession(id: UUID) async throws -> FocusSessionRecord

    // MARK: Tier B — approximate usage events

    /// Records a Tier B threshold-derived event. Always persisted with
    /// `precision: approximate`, `type: mobile_usage`, `source: mobile`, per
    /// [[architecture-mobile.md]] §2-3.
    @discardableResult
    func recordApproximateEvent(
        startedAt: Date,
        endedAt: Date,
        appBundleId: String?,
        categoryId: UUID?,
        projectId: UUID?
    ) async throws -> ActivityEventRecord

    // MARK: Fetching

    /// All non-tombstoned events and sessions whose activity overlaps today
    /// (the calendar day containing the store's current time).
    func fetchTodayData() async throws -> TodayData

    /// The currently-running session (`status == .running`, not tombstoned),
    /// regardless of which calendar day it started on.
    ///
    /// Unlike `fetchTodayData`, which is scoped to the calendar day
    /// containing the store's current time, this is day-agnostic — so a
    /// session started before midnight and still running is still found
    /// after the day rolls over. Used by `SessionEngine.recoverRunningSession`
    /// to correctly recover a session across a midnight boundary, and by the
    /// dashboard's running-session banner.
    func fetchActiveRunningSession() async throws -> FocusSessionRecord?

    /// Up to `limit` pending rows (events and sessions combined), ordered by
    /// `startedAt`, ready for the next sync push. `limit` must not exceed
    /// [[sync-protocol]]'s 500-items-per-batch cap.
    func fetchUnsyncedBatch(limit: Int) async throws -> UnsyncedBatch

    /// Marks the given event/session ids as synced as of now, e.g. after a
    /// push batch comes back with `applied` or `duplicate` results per
    /// [[sync-protocol]].
    func markSynced(eventIds: [UUID], sessionIds: [UUID]) async throws
}
