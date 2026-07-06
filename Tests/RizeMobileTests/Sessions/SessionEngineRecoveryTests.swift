import XCTest
@testable import RizeMobile

/// Relaunch-recovery and start/stop reentrancy tests for `SessionEngine`.
/// Split out of `SessionEngineTests` (RIZ-44 cleanup) purely to stay under
/// SwiftLint's file/type length limits — no behavioral difference from being
/// one file.
@MainActor
final class SessionEngineRecoveryTests: XCTestCase {
    /// Groups a freshly built `SessionEngine` with the collaborators used to
    /// construct it, so tests can drive the clock or inspect the store
    /// directly without a >2-member tuple (SwiftLint `large_tuple`).
    private struct MadeEngine {
        let engine: SessionEngine
        let store: GRDBLocalStore
        let clock: TestClock
    }

    private func makeEngine(clock: TestClock = TestClock()) throws -> MadeEngine {
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: clock,
            uuidGenerator: UUIDv7Generator(clock: clock)
        )
        let engine = SessionEngine(store: store, clock: clock, clockStateStore: InMemorySessionClockStore())
        return MadeEngine(engine: engine, store: store, clock: clock)
    }

    // MARK: relaunch recovery

    func testRecoverRunningSessionRestoresRunningStateFromTheStore() async throws {
        let made = try makeEngine()
        let store = made.store
        let clock = made.clock
        let started = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        clock.advance(by: 20)

        // Fresh engine instance simulating a relaunch, sharing the same store
        // but with no in-memory state and no persisted clock state.
        let relaunchedEngine = SessionEngine(store: store, clock: clock, clockStateStore: InMemorySessionClockStore())
        try await relaunchedEngine.recoverRunningSession()

        guard case let .running(snapshot) = relaunchedEngine.state else {
            return XCTFail("expected a recovered running session")
        }
        XCTAssertEqual(snapshot.id, started.id)
        // No persisted clock state existed, so elapsed is computed fresh from
        // the store's startedAt with zero accumulated pause.
        XCTAssertEqual(relaunchedEngine.elapsed(now: clock.now()), 20)
    }

    func testRecoverRunningSessionRestoresPausedStateFromPersistedClockState() async throws {
        let database = try AppDatabase.inMemory()
        let clock = TestClock()
        let store = GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: clock,
            uuidGenerator: UUIDv7Generator(clock: clock)
        )
        let clockStateStore = InMemorySessionClockStore()
        let engineWithSharedClockStore = SessionEngine(store: store, clock: clock, clockStateStore: clockStateStore)
        _ = try await engineWithSharedClockStore.start(kind: .focus)

        clock.advance(by: 10)
        try engineWithSharedClockStore.pause()
        clock.advance(by: 999) // must not count once recovered as paused

        let relaunchedEngine = SessionEngine(store: store, clock: clock, clockStateStore: clockStateStore)
        try await relaunchedEngine.recoverRunningSession()

        guard case .paused = relaunchedEngine.state else {
            return XCTFail("expected a recovered paused session")
        }
        XCTAssertEqual(relaunchedEngine.elapsed(now: clock.now()), 10)
    }

    func testRecoverRunningSessionRestoresASessionStartedBeforeMidnightAndStillRunning() async throws {
        let made = try makeEngine()
        let store = made.store
        let clock = made.clock
        let started = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)

        // Cross a midnight boundary while the session is still running.
        // `fetchTodayData` would no longer see it, but `recoverRunningSession`
        // must still recover it via the day-agnostic `fetchActiveRunningSession`.
        clock.advance(by: 2 * 86400)

        let relaunchedEngine = SessionEngine(store: store, clock: clock, clockStateStore: InMemorySessionClockStore())
        try await relaunchedEngine.recoverRunningSession()

        guard case let .running(snapshot) = relaunchedEngine.state else {
            return XCTFail("expected the pre-midnight session to be recovered as active")
        }
        XCTAssertEqual(snapshot.id, started.id)
        XCTAssertEqual(relaunchedEngine.elapsed(now: clock.now()), 2 * 86400)
    }

    func testRecoverRunningSessionIsIdleWhenNoSessionIsRunning() async throws {
        let made = try makeEngine()
        let engine = made.engine

        try await engine.recoverRunningSession()

        XCTAssertEqual(engine.state, .idle)
    }

    func testRecoverRunningSessionIgnoresCompletedSessions() async throws {
        let made = try makeEngine()
        let engine = made.engine
        let store = made.store
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        _ = try await store.stopSession(id: session.id, status: .completed)

        try await engine.recoverRunningSession()

        XCTAssertEqual(engine.state, .idle)
    }

    func testRecoverRunningSessionLeavesPersistedClockStateIntactWhenNoneIsRunning() async throws {
        let clock = TestClock()
        let store = SuspendingFakeStore()
        store.activeRunningSessionToReturn = nil
        let clockStateStore = InMemorySessionClockStore()
        let staleSessionId = UUID()
        let staleState = SessionClockState(startedAt: clock.now())
        clockStateStore.save(staleState, sessionId: staleSessionId)
        let engine = SessionEngine(store: store, clock: clock, clockStateStore: clockStateStore)

        let recoverTask = Task { try await engine.recoverRunningSession() }
        try await waitUntil { store.fetchCallCount > 0 }
        store.releaseFetch()
        try await recoverTask.value

        XCTAssertEqual(engine.state, .idle)
        // Not cleared: a future day-agnostic fetch may still need it.
        XCTAssertEqual(clockStateStore.load(sessionId: staleSessionId), staleState)
    }

    // MARK: reentrancy (RIZ-44 H1)

    func testConcurrentStartCallsAreRejectedWhileTheFirstIsInFlight() async throws {
        let store = SuspendingFakeStore()
        let startedAt = Date()
        store.recordToReturn = FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: .focus,
            startedAt: startedAt,
            status: .running,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let engine = SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())

        let firstStart = Task { try await engine.start(kind: .focus) }
        try await waitUntil { store.startCallCount > 0 }
        XCTAssertTrue(engine.isMutating)

        await XCTAssertThrowsErrorAsync(
            { try await engine.start(kind: .meeting) },
            { error in XCTAssertEqual(error as? SessionEngineError, .sessionAlreadyActive) }
        )

        store.releaseStart()
        let snapshot = try await firstStart.value

        XCTAssertEqual(store.startCallCount, 1, "the rejected call must never reach the store")
        XCTAssertEqual(engine.state, .running(snapshot))
        XCTAssertFalse(engine.isMutating)
    }

    func testConcurrentStopCallsAreRejectedWhileTheFirstIsInFlight() async throws {
        let made = try makeEngine()
        let stoppingStore = SuspendingFakeStoreWrappingStop(inner: made.store)
        let stoppingEngine = SessionEngine(
            store: stoppingStore,
            clock: made.clock,
            clockStateStore: InMemorySessionClockStore()
        )
        _ = try await stoppingEngine.start(kind: .focus)

        let firstStop = Task { try await stoppingEngine.stop(completed: true) }
        try await waitUntil { stoppingStore.stopCallCount > 0 }
        XCTAssertTrue(stoppingEngine.isMutating)

        await XCTAssertThrowsErrorAsync(
            { try await stoppingEngine.stop(completed: true) },
            { error in XCTAssertEqual(error as? SessionEngineError, .noActiveSession) }
        )

        stoppingStore.releaseStop()
        _ = try await firstStop.value

        XCTAssertEqual(stoppingStore.stopCallCount, 1, "the rejected call must never reach the store")
        XCTAssertEqual(stoppingEngine.state, .idle)
    }

    func testRecoverRunningSessionDoesNotClobberASessionStartedWhileItAwaitedTheStore() async throws {
        let store = SuspendingFakeStore()
        store.activeRunningSessionToReturn = nil
        let startedAt = Date()
        store.recordToReturn = FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: .focus,
            startedAt: startedAt,
            status: .running,
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let engine = SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())

        let recoverTask = Task { try await engine.recoverRunningSession() }
        try await waitUntil { store.fetchCallCount > 0 }

        let startTask = Task { try await engine.start(kind: .focus) }
        try await waitUntil { store.startCallCount > 0 }
        store.releaseStart()
        let startedSnapshot = try await startTask.value

        store.releaseFetch()
        try await recoverTask.value

        XCTAssertEqual(engine.state, .running(startedSnapshot))
    }

    /// Polls `condition` until it's true, yielding between checks, so tests
    /// can deterministically wait for a suspended call to reach its
    /// suspension point without a fixed `sleep`.
    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        while !condition() {
            await Task.yield()
        }
    }
}

/// A `LocalStoring` decorator that suspends `stopSession` until the test
/// releases it, forwarding everything else to `inner`. Used to exercise
/// `SessionEngine.stop`'s reentrancy guard without duplicating the full
/// `GRDBLocalStore` setup.
private final class SuspendingFakeStoreWrappingStop: LocalStoring, @unchecked Sendable {
    private let inner: LocalStoring
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var stopCallCount = 0

    init(inner: LocalStoring) {
        self.inner = inner
    }

    func releaseStop() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func startSession(
        kind: FocusSessionKind,
        projectId: UUID?,
        plannedDurationS: Int?,
        note: String?
    ) async throws -> FocusSessionRecord {
        try await inner.startSession(kind: kind, projectId: projectId, plannedDurationS: plannedDurationS, note: note)
    }

    func stopSession(id: UUID, status: FocusSessionStatus) async throws -> FocusSessionRecord {
        lock.lock()
        stopCallCount += 1
        lock.unlock()
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
        return try await inner.stopSession(id: id, status: status)
    }

    func editSession(id: UUID, projectId: UUID??, note: String??) async throws -> FocusSessionRecord {
        try await inner.editSession(id: id, projectId: projectId, note: note)
    }

    func deleteSession(id: UUID) async throws -> FocusSessionRecord {
        try await inner.deleteSession(id: id)
    }

    func recordApproximateEvent(
        startedAt: Date,
        endedAt: Date,
        appBundleId: String?,
        categoryId: UUID?,
        projectId: UUID?
    ) async throws -> ActivityEventRecord {
        try await inner.recordApproximateEvent(
            startedAt: startedAt,
            endedAt: endedAt,
            appBundleId: appBundleId,
            categoryId: categoryId,
            projectId: projectId
        )
    }

    func fetchTodayData() async throws -> TodayData {
        try await inner.fetchTodayData()
    }

    func fetchActiveRunningSession() async throws -> FocusSessionRecord? {
        try await inner.fetchActiveRunningSession()
    }

    func fetchUnsyncedBatch(limit: Int) async throws -> UnsyncedBatch {
        try await inner.fetchUnsyncedBatch(limit: limit)
    }

    func markSynced(events: [SyncedEventSnapshot], sessions: [SyncedSessionSnapshot]) async throws {
        try await inner.markSynced(events: events, sessions: sessions)
    }

    func applyEventChanges(upserts: [ActivityEventRecord], tombstoneIds: [UUID]) async throws {
        try await inner.applyEventChanges(upserts: upserts, tombstoneIds: tombstoneIds)
    }

    func applySessionChanges(upserts: [FocusSessionRecord], tombstoneIds: [UUID]) async throws {
        try await inner.applySessionChanges(upserts: upserts, tombstoneIds: tombstoneIds)
    }

    func wipeAllData() async throws {
        try await inner.wipeAllData()
    }
}
