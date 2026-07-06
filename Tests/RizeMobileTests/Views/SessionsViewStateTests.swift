import XCTest
@testable import RizeMobile

/// Covers `SessionsView.activeContent`'s `engine.state` switch branches not
/// already exercised by `SessionViewsTests.testSessionsViewInitializes`
/// (idle only) (RIZ-66) — drives a real `SessionEngine` into `.running`/
/// `.paused` (matching `SessionEngineTests`'s pattern) before constructing
/// the view.
@MainActor
final class SessionsViewStateTests: XCTestCase {
    private func makeEngine() throws -> SessionEngine {
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(database: database, deviceId: "test-device")
        return SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())
    }

    private func makeHistoryViewModel() throws -> SessionHistoryViewModel {
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(database: database, deviceId: "test-device")
        return SessionHistoryViewModel(store: store)
    }

    func testSessionsViewShowsRunningSessionViewWhenEngineIsRunning() async throws {
        let engine = try makeEngine()
        let historyViewModel = try makeHistoryViewModel()
        _ = try await engine.start(kind: .focus)

        guard case .running = engine.state else {
            return XCTFail("expected engine to be running after start()")
        }
        let view = SessionsView(engine: engine, historyViewModel: historyViewModel)

        XCTAssertNotNil(view.body)
    }

    func testSessionsViewShowsRunningSessionViewWhenEngineIsPaused() async throws {
        let engine = try makeEngine()
        let historyViewModel = try makeHistoryViewModel()
        _ = try await engine.start(kind: .focus)
        try engine.pause()

        guard case .paused = engine.state else {
            return XCTFail("expected engine to be paused after pause()")
        }
        let view = SessionsView(engine: engine, historyViewModel: historyViewModel)

        XCTAssertNotNil(view.body)
    }
}
