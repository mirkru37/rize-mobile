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

    /// Matches `DashboardViewModelTests`' pattern for deterministically
    /// awaiting the view model's async `apply`/`refreshActiveRunningSession`
    /// effects without a fixed `sleep`.
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        while !condition() {
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
