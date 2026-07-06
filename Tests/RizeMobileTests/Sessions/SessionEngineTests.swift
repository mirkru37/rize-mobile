import XCTest
@testable import RizeMobile

@MainActor
final class SessionEngineTests: XCTestCase {
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

    // MARK: start / pause / resume / stop

    func testStartTransitionsFromIdleToRunning() async throws {
        let made = try makeEngine()
        let engine = made.engine

        let snapshot = try await engine.start(kind: .focus, note: "deep work")

        XCTAssertEqual(engine.state, .running(snapshot))
        XCTAssertEqual(snapshot.kind, .focus)
        XCTAssertEqual(snapshot.note, "deep work")
    }

    func testStartWhileAlreadyActiveThrows() async throws {
        let made = try makeEngine()
        let engine = made.engine
        _ = try await engine.start(kind: .focus)

        await XCTAssertThrowsErrorAsync(
            { try await engine.start(kind: .meeting) },
            { error in XCTAssertEqual(error as? SessionEngineError, .sessionAlreadyActive) }
        )
    }

    func testPauseTransitionsRunningToPaused() async throws {
        let made = try makeEngine()
        let engine = made.engine
        let snapshot = try await engine.start(kind: .focus)

        try engine.pause()

        XCTAssertEqual(engine.state, .paused(snapshot))
    }

    func testPauseWithNoActiveSessionThrows() throws {
        let made = try makeEngine()
        let engine = made.engine

        XCTAssertThrowsError(try engine.pause()) { error in
            XCTAssertEqual(error as? SessionEngineError, .noActiveSession)
        }
    }

    func testResumeTransitionsPausedBackToRunning() async throws {
        let made = try makeEngine()
        let engine = made.engine
        let snapshot = try await engine.start(kind: .focus)
        try engine.pause()

        try engine.resume()

        XCTAssertEqual(engine.state, .running(snapshot))
    }

    func testResumeWithNoActiveSessionThrows() throws {
        let made = try makeEngine()
        let engine = made.engine

        XCTAssertThrowsError(try engine.resume()) { error in
            XCTAssertEqual(error as? SessionEngineError, .noActiveSession)
        }
    }

    func testStopTransitionsToIdleAndPersistsTerminalStatus() async throws {
        let made = try makeEngine()
        let engine = made.engine
        let store = made.store
        let clock = made.clock
        let snapshot = try await engine.start(kind: .focus)
        clock.advance(by: 60)

        let stopped = try await engine.stop(completed: true)

        XCTAssertEqual(engine.state, .idle)
        XCTAssertEqual(stopped.status, .completed)
        let today = try await store.fetchTodayData()
        XCTAssertEqual(today.sessions.first { $0.id == snapshot.id }?.status, .completed)
    }

    func testStopWithNoActiveSessionThrows() async throws {
        let made = try makeEngine()
        let engine = made.engine

        await XCTAssertThrowsErrorAsync(
            { try await engine.stop(completed: true) },
            { error in XCTAssertEqual(error as? SessionEngineError, .noActiveSession) }
        )
    }

    func testStopAfterPauseCanBeAbandoned() async throws {
        let made = try makeEngine()
        let engine = made.engine
        _ = try await engine.start(kind: .breakTime)
        try engine.pause()

        let stopped = try await engine.stop(completed: false)

        XCTAssertEqual(stopped.status, .abandoned)
        XCTAssertEqual(engine.state, .idle)
    }

    // MARK: elapsed time

    func testElapsedIsZeroWhenIdle() throws {
        let made = try makeEngine()
        let engine = made.engine

        XCTAssertEqual(engine.elapsed(now: Date()), 0)
    }

    func testElapsedAdvancesWithTheInjectedClockWhileRunning() async throws {
        let made = try makeEngine()
        let engine = made.engine
        let clock = made.clock
        _ = try await engine.start(kind: .focus)

        clock.advance(by: 45)

        XCTAssertEqual(engine.elapsed(now: clock.now()), 45)
    }

    func testElapsedFreezesWhilePausedAndResumesCounting() async throws {
        let made = try makeEngine()
        let engine = made.engine
        let clock = made.clock
        _ = try await engine.start(kind: .focus)

        clock.advance(by: 30)
        try engine.pause()
        clock.advance(by: 100) // time passes while paused; must not count
        XCTAssertEqual(engine.elapsed(now: clock.now()), 30)

        try engine.resume()
        clock.advance(by: 15)
        XCTAssertEqual(engine.elapsed(now: clock.now()), 45)
    }
}
