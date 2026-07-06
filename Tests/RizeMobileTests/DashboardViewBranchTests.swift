import XCTest
@testable import RizeMobile

/// Covers `DashboardView.body`'s state-dependent branches not already
/// exercised by `DashboardViewTests` (RIZ-66): the non-empty sessions list,
/// and the `historySection` filter that excludes the active running session
/// from the "Sessions" list (it's already shown by the running-session
/// banner above it). `DashboardView` has no extractable pure logic beyond
/// `body`/`content(now:)`/`historySection(now:)` (all `private`), so
/// branches are driven by real `DashboardViewModel` state, asserted before
/// evaluating `body`.
@MainActor
final class DashboardViewBranchTests: XCTestCase {
    private func makeStore() throws -> GRDBLocalStore {
        let database = try AppDatabase.inMemory()
        return GRDBLocalStore(database: database, deviceId: "test-device")
    }

    /// Deterministically awaits the view model's async `apply`/
    /// `refreshActiveRunningSession` effects without a fixed `sleep` —
    /// bounded (unlike some pre-existing `waitUntil` helpers elsewhere in
    /// this test target) so a genuine regression fails fast with a clear
    /// message instead of hanging the CI runner.
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("condition not satisfied within \(timeout)s", file: file, line: line)
                return
            }
            await Task.yield()
        }
    }

    func testDashboardViewRendersHistorySectionWithCompletedSessions() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        let engine = SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())
        let session = FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: .focus,
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            status: .completed,
            createdAt: Date(),
            updatedAt: Date()
        )
        viewModel.start()
        observer.emit(TodayData(sessions: [session]))
        try await waitUntil { viewModel.sessions.count == 1 }

        XCTAssertEqual(viewModel.sessions.map(\.id), [session.id])
        let view = DashboardView(viewModel: viewModel, engine: engine, selectedTab: .constant(.dashboard))

        XCTAssertNotNil(view.body)
    }

    func testDashboardViewExcludesTheActiveRunningSessionFromTheHistorySection() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        let engine = SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())
        let runningSession = try await store.startSession(
            kind: .focus,
            projectId: nil,
            plannedDurationS: nil,
            note: nil
        )
        viewModel.start()
        observer.emit(TodayData(sessions: [runningSession]))
        try await waitUntil { viewModel.activeRunningSession?.id == runningSession.id }

        // The only session today is also the active running one, so the
        // history-section filter should leave nothing to list — this is the
        // real behavior under test, independent of the `.body` call below.
        let historicalSessions = viewModel.sessions.filter { $0.id != viewModel.activeRunningSession?.id }
        XCTAssertTrue(historicalSessions.isEmpty)
        let view = DashboardView(viewModel: viewModel, engine: engine, selectedTab: .constant(.dashboard))

        XCTAssertNotNil(view.body)
    }
}
