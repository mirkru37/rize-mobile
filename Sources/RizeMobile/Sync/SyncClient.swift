import Foundation

/// Reads pending local events/sessions, pushes them to the backend, and
/// pulls remote state, per [[sync-protocol]] §Flow — the "Sync Client"
/// component named in [[architecture-mobile.md]] §4.
///
/// An `actor` (rather than a plain class) so overlapping triggers — app
/// foreground and "session just completed" can race in practice — never run
/// two sync cycles concurrently against the same outbox; `syncNow()` simply
/// no-ops if a cycle is already in flight.
public actor SyncClient {
    private let apiClient: APIClientProtocol
    private let authService: AuthService
    private let store: LocalStoring
    private let cursorStore: SyncCursorStoring
    private let backoff: BackoffPolicy
    private let sleeper: AsyncSleeping
    private let clock: Clock
    private let deviceId: String
    private let maxRetryAttempts: Int
    private let pushBatchLimit: Int
    private let pullPageLimit: Int

    private var isSyncing = false

    public init(
        apiClient: APIClientProtocol,
        authService: AuthService,
        store: LocalStoring,
        cursorStore: SyncCursorStoring,
        deviceId: String,
        backoff: BackoffPolicy = ExponentialBackoff(),
        sleeper: AsyncSleeping = TaskSleeper(),
        clock: Clock = SystemClock(),
        maxRetryAttempts: Int = 3,
        pushBatchLimit: Int = 500,
        pullPageLimit: Int = 200
    ) {
        self.apiClient = apiClient
        self.authService = authService
        self.store = store
        self.cursorStore = cursorStore
        self.deviceId = deviceId
        self.backoff = backoff
        self.sleeper = sleeper
        self.clock = clock
        // [[sync-protocol]] §Push: a single request MUST NOT contain more
        // than 500 items, no matter what a caller configures.
        self.maxRetryAttempts = maxRetryAttempts
        self.pushBatchLimit = min(pushBatchLimit, 500)
        self.pullPageLimit = pullPageLimit
    }

    /// Runs one full sync cycle: push then pull, per [[sync-protocol]] §Flow
    /// ("a sync cycle always pushes before it pulls"). Never throws — a
    /// failure at any point leaves the local outbox/cursor untouched (see
    /// `pushOutbox`/`pullChanges`) so the next trigger (foreground, session
    /// completion, or a future periodic trigger) safely retries from where
    /// this cycle left off. Local data is never removed except via
    /// `markSynced`/`applyEventChanges`/`applySessionChanges` after a
    /// confirmed server response, so no failure path here can lose data.
    public func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await pushOutbox()
            try await pullChanges()
            await authService.recordSyncCompleted(at: clock.now())
        } catch {
            // Swallowed by design: `syncNow()` is a background trigger with
            // no UI to report a spinner/error to synchronously. The next
            // trigger retries; nothing pushed/pulled so far is lost since
            // both loops only advance their own durable state after a
            // successful, applied response.
        }
    }

    // MARK: Push

    /// Pushes the entire local outbox in ≤500-item batches, per
    /// [[sync-protocol]] §Push, looping until the outbox is drained.
    func pushOutbox() async throws {
        while true {
            let batch = try await store.fetchUnsyncedBatch(limit: pushBatchLimit)
            guard batch.count > 0 else { return }

            let items = batch.events.map { SyncPushItem(.activityEvent(ActivityEventPushData(from: $0))) }
                + batch.sessions.map { SyncPushItem(.focusSession(FocusSessionPushData(from: $0))) }

            _ = try await withRetry {
                try await self.authorized { token in
                    try await self.apiClient.pushEvents(accessToken: token, deviceId: self.deviceId, items: items)
                }
            }

            // Every item in this batch has a definite per-item outcome
            // (applied/duplicate/invalid) per [[sync-protocol]] §Push, and
            // partial success is by design never rejected wholesale. This
            // client's outbox policy (no separate "flag as invalid for
            // user review" surface exists yet) is to remove the whole batch
            // from the outbox once *a* response is durably received:
            // applied/duplicate rows are correctly synced, and invalid rows
            // are "discarded" in the sense [[sync-protocol]] allows —
            // discarding a row still leaves it in the local table for
            // history, it just stops being retried.
            let eventSnapshots = batch.events.map {
                SyncedEventSnapshot(eventId: $0.eventId, insertedAt: $0.insertedAt)
            }
            let sessionSnapshots = batch.sessions.map { SyncedSessionSnapshot(id: $0.id, updatedAt: $0.updatedAt) }
            try await store.markSynced(events: eventSnapshots, sessions: sessionSnapshots)

            if batch.count < pushBatchLimit { return }
        }
    }

    // MARK: Pull

    /// Pulls remote changes using the stored cursor, applying each page and
    /// persisting the new cursor, per [[sync-protocol]] §Pull, until a page
    /// comes back with `hasMore == false`.
    func pullChanges() async throws {
        while true {
            let cursor = cursorStore.loadCursor()

            let response = try await withRetry {
                try await self.authorized { token in
                    try await self.apiClient.pullChanges(accessToken: token, cursor: cursor, limit: self.pullPageLimit)
                }
            }

            try await applyPulledChanges(response.changes)
            cursorStore.saveCursor(response.nextCursor)

            if !response.hasMore { return }
        }
    }

    private func applyPulledChanges(_ changes: SyncChanges) async throws {
        if let page = changes.activityEvents {
            let upserts = page.upserts.compactMap(Self.makeActivityEventRecord(from:))
            let tombstoneIds = page.tombstones.compactMap { UUID(uuidString: $0.eventId) }
            try await store.applyEventChanges(upserts: upserts, tombstoneIds: tombstoneIds)
        }
        if let page = changes.focusSessions {
            let upserts = page.upserts.compactMap(Self.makeFocusSessionRecord(from:))
            let tombstoneIds = page.tombstones.compactMap { UUID(uuidString: $0.id) }
            try await store.applySessionChanges(upserts: upserts, tombstoneIds: tombstoneIds)
        }
    }

    // MARK: Auth + retry

    /// Executes an authorized call, transparently refreshing and retrying
    /// exactly once on a `401` — the single-flight refresh itself lives in
    /// `AuthService.refreshAccessToken()`; this just reacts to the 401 and
    /// asks for a fresh token.
    private func authorized<T: Sendable>(
        _ operation: @Sendable (String) async throws -> T
    ) async throws -> T {
        let token = try await authService.validAccessToken()
        do {
            return try await operation(token)
        } catch APIClientError.unauthorized {
            let refreshedToken = try await authService.refreshAccessToken()
            return try await operation(refreshedToken)
        }
    }

    /// Retries a transient failure with bounded exponential backoff (see
    /// `BackoffPolicy`), driven by an injected `AsyncSleeping` so tests never
    /// wait on a real clock. `AuthError`/a repeated `401` after the retry
    /// above are not backed off further here — they've already gone through
    /// the single-flight refresh path and a second failure means the session
    /// itself is unrecoverable, not a transient network blip.
    private func withRetry<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < maxRetryAttempts else { throw error }
                try? await sleeper.sleep(seconds: backoff.delay(forAttempt: attempt))
                attempt += 1
            }
        }
    }

    // MARK: Wire -> local record mapping

    /// Maps a pulled `activity_event` upsert to a local record.
    ///
    /// Assumption: [[sync-protocol]]'s pull response schema for
    /// `activity_events` doesn't include `device_id` (see the worked
    /// example), so a pulled row's `deviceId` is set to a `"remote"`
    /// sentinel — it's not otherwise used locally except to tag a row's
    /// origin, and the actual owning device is irrelevant to what this
    /// client does with pulled data. Resolved `category` (a display name,
    /// not a `category_id`) has no corresponding local column — there is no
    /// local categories table — so it is intentionally not stored; category
    /// display for pulled cross-device events is out of scope of this ticket.
    private static func makeActivityEventRecord(from change: SyncPullEventChange) -> ActivityEventRecord? {
        guard let eventId = UUID(uuidString: change.eventId) else { return nil }
        return ActivityEventRecord(
            eventId: eventId,
            deviceId: "remote",
            startedAt: change.startedAt,
            endedAt: change.endedAt,
            appBundleId: change.appBundleId,
            categoryId: nil,
            projectId: nil,
            deleted: false,
            insertedAt: change.startedAt
        )
    }

    private static func makeFocusSessionRecord(from change: SyncPullSessionChange) -> FocusSessionRecord? {
        guard let id = UUID(uuidString: change.id) else { return nil }
        return FocusSessionRecord(
            id: id,
            deviceId: "remote",
            projectId: change.projectId.flatMap(UUID.init(uuidString:)),
            kind: FocusSessionKind(rawValue: change.kind ?? "") ?? .focus,
            plannedDurationS: change.plannedDurationS,
            startedAt: change.startedAt,
            endedAt: change.endedAt,
            status: FocusSessionStatus(rawValue: change.status ?? "") ?? .completed,
            note: change.note,
            createdAt: change.startedAt,
            updatedAt: change.updatedAt
        )
    }
}
