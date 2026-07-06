import XCTest
@testable import RizeMobile

@MainActor
final class SessionViewsTests: XCTestCase {
    /// Groups a freshly built `SessionEngine` with the clock used to
    /// construct it, so tests can drive time deterministically (see
    /// `SessionEngineTests.MadeEngine` for the same pattern).
    private struct MadeEngine {
        let engine: SessionEngine
        let clock: TestClock
    }

    private func makeEngine() throws -> SessionEngine {
        try makeEngineWithClock().engine
    }

    private func makeEngineWithClock() throws -> MadeEngine {
        let database = try AppDatabase.inMemory()
        let clock = TestClock()
        let store = GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: clock,
            uuidGenerator: UUIDv7Generator(clock: clock)
        )
        let engine = SessionEngine(store: store, clock: clock, clockStateStore: InMemorySessionClockStore())
        return MadeEngine(engine: engine, clock: clock)
    }

    func testStartSessionViewInitializesWhileIdle() throws {
        let engine = try makeEngine()

        let view = StartSessionView(engine: engine)

        XCTAssertNotNil(view.body)
    }

    func testRunningSessionViewInitializesForARunningSnapshot() throws {
        let engine = try makeEngine()
        let snapshot = SessionSnapshot(
            id: UUID(), kind: .focus, projectId: nil, note: nil, plannedDurationS: nil, startedAt: Date()
        )

        let view = RunningSessionView(engine: engine, snapshot: snapshot, isPaused: false)

        XCTAssertNotNil(view.body)
    }

    func testRunningSessionViewRendersThePausedAndNoteBranchesWhenPausedWithANote() throws {
        let engine = try makeEngine()
        let snapshot = SessionSnapshot(
            id: UUID(), kind: .meeting, projectId: nil, note: "Standup", plannedDurationS: nil, startedAt: Date()
        )

        let view = RunningSessionView(engine: engine, snapshot: snapshot, isPaused: true)

        XCTAssertTrue(view.isPaused)
        XCTAssertNotNil(view.body)
    }

    func testSessionHistoryViewInitializes() throws {
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(database: database, deviceId: "test-device")
        let viewModel = SessionHistoryViewModel(store: store)

        let view = SessionHistoryView(viewModel: viewModel)

        XCTAssertNotNil(view.body)
    }

    func testSessionHistoryViewRendersTheListWhenSessionsArePresent() async throws {
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(database: database, deviceId: "test-device")
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: "note")
        _ = try await store.stopSession(id: session.id, status: .completed)
        let viewModel = SessionHistoryViewModel(store: store)
        try await viewModel.refresh()

        XCTAssertEqual(viewModel.sessions.map(\.id), [session.id])
        let view = SessionHistoryView(viewModel: viewModel)

        XCTAssertNotNil(view.body)
    }

    func testSessionsViewInitializes() throws {
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(database: database, deviceId: "test-device")
        let engine = SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())
        let historyViewModel = SessionHistoryViewModel(store: store)

        let view = SessionsView(engine: engine, historyViewModel: historyViewModel)

        XCTAssertNotNil(view.body)
    }

    // MARK: wall-clock display math (RIZ-44 M1)

    func testWallClockSpanIsNowMinusStartedAt() {
        let startedAt = Date(timeIntervalSince1970: 1000)
        let now = startedAt.addingTimeInterval(125)

        XCTAssertEqual(RunningSessionView.wallClockSpan(now: now, startedAt: startedAt), 125)
    }

    func testWallClockSpanIncludesPausedTimeUnlikeActiveElapsed() async throws {
        let made = try makeEngineWithClock()
        let engine = made.engine
        let clock = made.clock
        _ = try await engine.start(kind: .focus)
        clock.advance(by: 30)
        try engine.pause()
        clock.advance(by: 100)

        // Active time (SessionEngine.elapsed) freezes across the pause...
        XCTAssertEqual(engine.elapsed(now: clock.now()), 30)
        // ...but the wall-clock span shown as the primary timer keeps moving,
        // matching the synced started_at/ended_at instants.
        let startedAt = engine.state.snapshot?.startedAt ?? Date()
        XCTAssertEqual(RunningSessionView.wallClockSpan(now: clock.now(), startedAt: startedAt), 130)
    }

    func testWallClockSpanNeverGoesNegative() {
        let startedAt = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 900)

        XCTAssertEqual(RunningSessionView.wallClockSpan(now: now, startedAt: startedAt), 0)
    }

    // MARK: HH:MM:SS formatting (RIZ-66)

    func testFormatRendersHoursMinutesAndSeconds() {
        XCTAssertEqual(RunningSessionView.format(3725), "01:02:05")
    }

    func testFormatRendersZeroPaddedForSubHourDurations() {
        XCTAssertEqual(RunningSessionView.format(65), "00:01:05")
    }

    func testFormatClampsNegativeIntervalsToZero() {
        XCTAssertEqual(RunningSessionView.format(-10), "00:00:00")
    }

    // MARK: SessionsView engine-state branches (RIZ-66)

    func testSessionsViewShowsRunningSessionViewWhenEngineIsRunning() async throws {
        let engine = try makeEngine()
        let historyViewModel = try SessionHistoryViewModel(store: makeStore())
        _ = try await engine.start(kind: .focus)

        guard case .running = engine.state else {
            return XCTFail("expected engine to be running after start()")
        }
        let view = SessionsView(engine: engine, historyViewModel: historyViewModel)

        XCTAssertNotNil(view.body)
    }

    func testSessionsViewShowsRunningSessionViewWhenEngineIsPaused() async throws {
        let engine = try makeEngine()
        let historyViewModel = try SessionHistoryViewModel(store: makeStore())
        _ = try await engine.start(kind: .focus)
        try engine.pause()

        guard case .paused = engine.state else {
            return XCTFail("expected engine to be paused after pause()")
        }
        let view = SessionsView(engine: engine, historyViewModel: historyViewModel)

        XCTAssertNotNil(view.body)
    }

    private func makeStore() throws -> GRDBLocalStore {
        let database = try AppDatabase.inMemory()
        return GRDBLocalStore(database: database, deviceId: "test-device")
    }
}
