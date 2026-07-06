import XCTest
@testable import RizeMobile

@MainActor
final class DashboardViewTests: XCTestCase {
    private func makeStore() throws -> GRDBLocalStore {
        let database = try AppDatabase.inMemory()
        return GRDBLocalStore(database: database, deviceId: "test-device")
    }

    func testDashboardViewInitializes() throws {
        let store = try makeStore()
        let viewModel = DashboardViewModel(store: store, observer: StubTodayDataObserver())
        let engine = SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())

        let view = DashboardView(viewModel: viewModel, engine: engine, selectedTab: .constant(.dashboard))

        XCTAssertNotNil(view.body)
    }

    func testDashboardEmptyStateViewInitializes() {
        let view = DashboardEmptyStateView(selectedTab: .constant(.dashboard))

        XCTAssertNotNil(view.body)
    }

    func testDashboardRunningSessionBannerInitializes() throws {
        let store = try makeStore()
        let engine = SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())
        let session = FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: .focus,
            startedAt: Date(),
            status: .running,
            createdAt: Date(),
            updatedAt: Date()
        )

        let view = DashboardRunningSessionBanner(engine: engine, session: session, now: Date())

        XCTAssertNotNil(view.body)
    }

    func testDashboardSessionRowInitializes() {
        let session = FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: .meeting,
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            status: .completed,
            createdAt: Date(),
            updatedAt: Date()
        )

        let view = DashboardSessionRow(session: session, now: Date())

        XCTAssertNotNil(view.body)
    }

    func testRootViewInitializes() {
        let view = RootView(environment: .inMemory())

        XCTAssertNotNil(view.body)
    }

    func testRootViewRendersTheErrorStateWithoutCrashingWhenTheEnvironmentFailedToOpen() {
        let view = RootView(environmentResult: .failure(CocoaError(.fileWriteUnknown)))

        XCTAssertNotNil(view.body)
    }

    func testDashboardViewInitializesWhenTheViewModelHasALoadError() throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        let engine = SessionEngine(store: store, clockStateStore: InMemorySessionClockStore())
        viewModel.start()
        observer.emitError(CocoaError(.fileReadUnknown))

        let view = DashboardView(viewModel: viewModel, engine: engine, selectedTab: .constant(.dashboard))

        XCTAssertNotNil(view.body)
    }
}
