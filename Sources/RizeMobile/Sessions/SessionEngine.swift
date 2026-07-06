import Foundation
import Observation

/// An immutable, in-memory snapshot of the currently active session's
/// identifying fields, for driving UI without re-fetching from the store.
public struct SessionSnapshot: Equatable, Sendable {
    public var id: UUID
    public var kind: FocusSessionKind
    public var projectId: UUID?
    public var note: String?
    public var plannedDurationS: Int?
    public var startedAt: Date

    public init(
        id: UUID,
        kind: FocusSessionKind,
        projectId: UUID?,
        note: String?,
        plannedDurationS: Int?,
        startedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.projectId = projectId
        self.note = note
        self.plannedDurationS = plannedDurationS
        self.startedAt = startedAt
    }
}

/// The Tier C session engine's current lifecycle state, per
/// [[architecture-mobile.md]] §Tier C.
public enum SessionEngineState: Equatable, Sendable {
    case idle
    case running(SessionSnapshot)
    case paused(SessionSnapshot)

    var snapshot: SessionSnapshot? {
        switch self {
        case .idle:
            nil
        case let .running(snapshot), let .paused(snapshot):
            snapshot
        }
    }
}

/// Errors surfaced by `SessionEngine`.
public enum SessionEngineError: Error, Equatable {
    /// `start` was called while a session was already running or paused.
    case sessionAlreadyActive
    /// `pause`/`resume`/`stop` was called with no active session.
    case noActiveSession
}

/// Drives the Tier C manual timer / focus session lifecycle: start, pause,
/// resume, stop, and relaunch recovery.
///
/// This is the view-model layer's session controller: it depends only on
/// `LocalStoring` and `SessionClockStoring` (both protocols), never on
/// `GRDBLocalStore` directly, so views never touch the store and tests can
/// substitute in-memory fakes for both collaborators plus an injected
/// `Clock`, per [[architecture-mobile.md]] and this repo's MVVM convention.
@MainActor
@Observable
public final class SessionEngine {
    public private(set) var state: SessionEngineState = .idle

    /// `true` while `start`/`stop` is between its synchronous guard and its
    /// commit of the new state, i.e. currently awaiting the store. `@MainActor`
    /// is reentrant across suspension points, so this synchronous flag — set
    /// before the first `await` — is what actually prevents two concurrent
    /// calls from both passing the `.idle`/active guard (the guard alone is
    /// not enough: a second call can run its synchronous prefix while the
    /// first is suspended awaiting the store). Exposed so UI can disable
    /// Start/Stop controls while a mutation is in flight.
    public private(set) var isMutating = false

    private let store: LocalStoring
    private let clock: Clock
    private let clockStateStore: SessionClockStoring
    private var clockState: SessionClockState?

    public init(store: LocalStoring, clock: Clock = SystemClock(), clockStateStore: SessionClockStoring) {
        self.store = store
        self.clock = clock
        self.clockStateStore = clockStateStore
    }

    // MARK: Relaunch recovery

    /// Reconciles in-memory state against the local store's durable record of
    /// a running session, so a session survives an app relaunch. Should be
    /// called once, early in the app/screen's lifecycle.
    ///
    /// Note: this relies on `LocalStoring.fetchTodayData()`, which is scoped
    /// to the current calendar day; a session still running across a
    /// midnight boundary will not be recovered by this call. When no running
    /// session is found, only the in-memory state is reset to `.idle` — the
    /// persisted clock state is left intact rather than cleared, since a
    /// future day-agnostic fetch may still need it to recover pause state.
    public func recoverRunningSession() async throws {
        guard case .idle = state, !isMutating else { return }

        let today = try await store.fetchTodayData()

        // A concurrent start()/stop() may have already committed a new state
        // while this call was awaiting the store above; never clobber it.
        guard case .idle = state, !isMutating else { return }

        guard let running = today.sessions.first(where: { $0.status == .running && $0.deletedAt == nil }) else {
            state = .idle
            return
        }

        let restored = clockStateStore.load(sessionId: running.id) ?? SessionClockState(startedAt: running.startedAt)
        clockState = restored
        let snapshot = Self.snapshot(of: running)
        state = restored.pausedAt == nil ? .running(snapshot) : .paused(snapshot)
    }

    // MARK: Lifecycle

    /// Starts a new manual timer / focus session. Throws `sessionAlreadyActive`
    /// if a session is already running or paused, or if a start/stop mutation
    /// is already in flight.
    @discardableResult
    public func start(
        kind: FocusSessionKind,
        projectId: UUID? = nil,
        plannedDurationS: Int? = nil,
        note: String? = nil
    ) async throws -> SessionSnapshot {
        guard case .idle = state, !isMutating else { throw SessionEngineError.sessionAlreadyActive }
        isMutating = true
        defer { isMutating = false }

        let record = try await store.startSession(
            kind: kind,
            projectId: projectId,
            plannedDurationS: plannedDurationS,
            note: note
        )

        // Defensive re-check: nothing else should have been able to commit a
        // transition while isMutating was true, but never overwrite a state
        // that has already moved away from .idle.
        guard case .idle = state else { throw SessionEngineError.sessionAlreadyActive }

        let newClockState = SessionClockState(startedAt: record.startedAt)
        clockState = newClockState
        clockStateStore.save(newClockState, sessionId: record.id)
        let snapshot = Self.snapshot(of: record)
        state = .running(snapshot)
        return snapshot
    }

    /// Pauses the running session. Throws `noActiveSession` if idle or
    /// already paused.
    public func pause() throws {
        guard case let .running(snapshot) = state, var clockState else {
            throw SessionEngineError.noActiveSession
        }
        clockState.pause(at: clock.now())
        self.clockState = clockState
        clockStateStore.save(clockState, sessionId: snapshot.id)
        state = .paused(snapshot)
    }

    /// Resumes a paused session. Throws `noActiveSession` if idle or already
    /// running.
    public func resume() throws {
        guard case let .paused(snapshot) = state, var clockState else {
            throw SessionEngineError.noActiveSession
        }
        clockState.resume(at: clock.now())
        self.clockState = clockState
        clockStateStore.save(clockState, sessionId: snapshot.id)
        state = .running(snapshot)
    }

    /// Stops the active session (running or paused), persisting it as
    /// `completed` or `abandoned`. Clears the pause-state persistence, since
    /// a stopped session has nothing left to recover on relaunch. Throws
    /// `noActiveSession` if idle or if a start/stop mutation is already in
    /// flight.
    @discardableResult
    public func stop(completed: Bool) async throws -> FocusSessionRecord {
        guard !isMutating, let snapshot = state.snapshot else {
            throw SessionEngineError.noActiveSession
        }
        isMutating = true
        defer { isMutating = false }

        let record = try await store.stopSession(id: snapshot.id, status: completed ? .completed : .abandoned)
        clockStateStore.clear()
        clockState = nil
        state = .idle
        return record
    }

    // MARK: Elapsed time

    /// Elapsed active time of the current session as of `now`, or `0` if
    /// idle. Pure with respect to the injected `Clock`/caller-supplied `now`,
    /// so it is deterministic in tests and drivable by a `TimelineView` in UI.
    public func elapsed(now: Date) -> TimeInterval {
        clockState?.elapsed(now: now) ?? 0
    }

    private static func snapshot(of record: FocusSessionRecord) -> SessionSnapshot {
        SessionSnapshot(
            id: record.id,
            kind: record.kind,
            projectId: record.projectId,
            note: record.note,
            plannedDurationS: record.plannedDurationS,
            startedAt: record.startedAt
        )
    }
}
