import XCTest
@testable import RizeMobile

@MainActor
final class SessionViewsTests: XCTestCase {
    private func makeEngine() throws -> SessionEngine {
        let database = try AppDatabase.inMemory()
        let clock = TestClock()
        let store = GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: clock,
            uuidGenerator: UUIDv7Generator(clock: clock)
        )
        return SessionEngine(store: store, clock: clock, clockStateStore: InMemorySessionClockStore())
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

    func testSessionHistoryViewInitializes() throws {
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(database: database, deviceId: "test-device")
        let viewModel = SessionHistoryViewModel(store: store)

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
}
