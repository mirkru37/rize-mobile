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

    public var isEmpty: Bool {
        events.isEmpty && sessions.isEmpty
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

/// A snapshot of a Tier B event's version-relevant fields at the moment it
/// was read into a push batch. `insertedAt` never changes after creation
/// (Tier B events have no in-place mutation path today), so the guard below
/// always matches for events — it exists for symmetry with
/// `SyncedSessionSnapshot` and so a future mutation path (e.g. an event-level
/// tombstone) is covered automatically.
public struct SyncedEventSnapshot: Equatable, Sendable {
    public var eventId: UUID
    public var insertedAt: Date

    public init(eventId: UUID, insertedAt: Date) {
        self.eventId = eventId
        self.insertedAt = insertedAt
    }
}

/// A snapshot of a Tier C session's version-relevant field (`updatedAt`) at
/// the moment it was read into a push batch. Passed back into `markSynced`
/// so the store can detect a local edit that raced with an in-flight push
/// (RIZ-43 review finding M1): `editSession`/`stopSession`/`deleteSession`
/// all bump `updatedAt`, so a mismatch means the row changed after the batch
/// was fetched and must not be marked synced, or the newer local edit would
/// be silently dropped from the next outbox pass.
public struct SyncedSessionSnapshot: Equatable, Sendable {
    public var id: UUID
    public var updatedAt: Date

    public init(id: UUID, updatedAt: Date) {
        self.id = id
        self.updatedAt = updatedAt
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

    /// Marks the given events/sessions as synced as of now, e.g. after a push
    /// batch comes back with `applied` or `duplicate` results per
    /// [[sync-protocol]].
    ///
    /// **Guard (RIZ-46, carried over from RIZ-43 review finding M1):** a row
    /// is only flipped to synced if its *current* version-relevant field
    /// (`updatedAt` for sessions, `insertedAt` for events) still matches the
    /// snapshot the caller took when the batch was originally fetched for
    /// push. If the row changed locally in the meantime (e.g. the user edited
    /// a session while its push was in flight), that row is left pending so
    /// the newer local state is not silently skipped on the next sync pass.
    func markSynced(events: [SyncedEventSnapshot], sessions: [SyncedSessionSnapshot]) async throws

    // MARK: Applying pulled changes

    /// Applies a page of pulled Tier B `activity_events` upserts/tombstones
    /// from `GET /v1/sync/changes`. Append-only entity per [[sync-protocol]]:
    /// an upsert is an unconditional insert-or-replace by `eventId` (no LWW
    /// comparison needed), and a tombstone sets `deleted = true`. Applied rows
    /// are marked `syncedAt = now`, since a row just pulled from the server is
    /// by definition consistent with it.
    func applyEventChanges(upserts: [ActivityEventRecord], tombstoneIds: [UUID]) async throws

    /// Applies a page of pulled Tier C `focus_sessions` upserts/tombstones
    /// from `GET /v1/sync/changes`, using last-write-wins semantics per
    /// [[sync-protocol]]: an incoming upsert only overwrites a locally-known
    /// row if its `updatedAt` is not older than the local row's `updatedAt`
    /// (a tie favors the incoming server row, since the server has already
    /// resolved LWW authoritatively). Applied rows are marked
    /// `syncedAt = now`.
    func applySessionChanges(upserts: [FocusSessionRecord], tombstoneIds: [UUID]) async throws

    // MARK: Logout

    /// Wipes all locally stored events and sessions.
    ///
    /// This app is single-user-per-install, so on logout there is no
    /// multi-account local cache to preserve — signing out means the local
    /// data belongs to an account this install is no longer authenticated as,
    /// and keeping it around would let a subsequent sign-in (as a different
    /// user, on a shared/reset device) see a previous user's tracked
    /// activity. The device id is deliberately untouched by this call (see
    /// `AuthService.logout()`).
    func wipeAllData() async throws
}
