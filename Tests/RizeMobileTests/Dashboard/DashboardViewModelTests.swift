import XCTest
@testable import RizeMobile

@MainActor
final class DashboardViewModelTests: XCTestCase {
    private func makeStore(clock: TestClock = TestClock()) throws -> GRDBLocalStore {
        let database = try AppDatabase.inMemory()
        return GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: clock,
            uuidGenerator: UUIDv7Generator(clock: clock)
        )
    }

    private func makeSession(
        kind: FocusSessionKind = .focus,
        startedAt: Date,
        endedAt: Date? = nil,
        status: FocusSessionStatus = .completed
    ) -> FocusSessionRecord {
        FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: kind,
            startedAt: startedAt,
            endedAt: endedAt,
            status: status,
            createdAt: startedAt,
            updatedAt: startedAt
        )
    }

    /// Polls `condition` until it's true, yielding between checks, matching
    /// `SessionEngineRecoveryTests`'s pattern for deterministically awaiting
    /// an async effect without a fixed `sleep`.
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        while !condition() {
            await Task.yield()
        }
    }

    // MARK: reactivity

    func testSessionsUpdateWhenTheObserverEmitsANewSnapshot() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        let now = Date(timeIntervalSince1970: 10000)
        let sessionA = makeSession(startedAt: now.addingTimeInterval(-3600), endedAt: now.addingTimeInterval(-3300))
        let sessionB = makeSession(
            kind: .meeting,
            startedAt: now.addingTimeInterval(-600),
            endedAt: now.addingTimeInterval(-300)
        )

        viewModel.start()
        XCTAssertEqual(observer.observeCallCount, 1)
        observer.emit(TodayData(sessions: [sessionA, sessionB]))
        try await waitUntil { viewModel.sessions.count == 2 }

        XCTAssertEqual(Set(viewModel.sessions.map(\.id)), [sessionA.id, sessionB.id])
    }

    func testSessionsAreSortedMostRecentFirst() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        let now = Date(timeIntervalSince1970: 10000)
        let earlier = makeSession(startedAt: now.addingTimeInterval(-3600), endedAt: now.addingTimeInterval(-3300))
        let later = makeSession(startedAt: now.addingTimeInterval(-600), endedAt: now.addingTimeInterval(-300))

        viewModel.start()
        observer.emit(TodayData(sessions: [earlier, later]))
        try await waitUntil { viewModel.sessions.count == 2 }

        XCTAssertEqual(viewModel.sessions.map(\.id), [later.id, earlier.id])
    }

    // MARK: aggregation

    func testTotalTrackedDurationSumsWallClockSpansOfTodaysSessions() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        let now = Date(timeIntervalSince1970: 10000)
        let sessionA = makeSession(startedAt: now.addingTimeInterval(-3600), endedAt: now.addingTimeInterval(-3300))
        let sessionB = makeSession(
            kind: .meeting,
            startedAt: now.addingTimeInterval(-600),
            endedAt: now.addingTimeInterval(-300)
        )

        viewModel.start()
        observer.emit(TodayData(sessions: [sessionA, sessionB]))
        try await waitUntil { viewModel.sessions.count == 2 }

        XCTAssertEqual(viewModel.totalTrackedDuration(now: now), 300 + 300)
    }

    func testTotalTrackedDurationIncludesWallClockSpanOfARunningSessionAsOfNow() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        let now = Date(timeIntervalSince1970: 10000)
        let running = makeSession(startedAt: now.addingTimeInterval(-120), status: .running)

        viewModel.start()
        observer.emit(TodayData(sessions: [running]))
        try await waitUntil { viewModel.sessions.count == 1 }

        // No `endedAt`, so the wall-clock span runs through to `now` — this
        // matches the Tier C pause-semantics decision (wall-clock,
        // including any paused time, is authoritative for the recorded
        // duration).
        XCTAssertEqual(viewModel.totalTrackedDuration(now: now), 120)
    }

    func testFormattedDurationFormatsAsHoursMinutesSeconds() {
        XCTAssertEqual(DashboardViewModel.formattedDuration(3661), "01:01:01")
    }

    func testWallClockDurationOfSessionNeverGoesNegative() {
        let startedAt = Date(timeIntervalSince1970: 1000)
        let now = Date(timeIntervalSince1970: 900)
        let session = makeSession(startedAt: startedAt, endedAt: nil, status: .running)

        XCTAssertEqual(DashboardViewModel.wallClockDuration(of: session, now: now), 0)
    }

    // MARK: running-session banner

    func testActiveRunningSessionReflectsFetchActiveRunningSessionFromTheStore() async throws {
        let store = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)

        viewModel.start()
        try await waitUntil { viewModel.activeRunningSession?.id == session.id }

        XCTAssertEqual(viewModel.activeRunningSession?.id, session.id)
    }

    func testActiveRunningSessionIsNilWhenNothingIsRunning() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)

        viewModel.start()
        observer.emit(TodayData())
        try await waitUntil { observer.observeCallCount > 0 }

        XCTAssertNil(viewModel.activeRunningSession)
    }

    func testActiveRunningSessionUpdatesAfterTheSessionIsStopped() async throws {
        let store = try makeStore()
        let session = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        viewModel.start()
        try await waitUntil { viewModel.activeRunningSession?.id == session.id }

        _ = try await store.stopSession(id: session.id, status: .completed)
        observer.emit(observer.current) // simulate the table-change notification

        try await waitUntil { viewModel.activeRunningSession == nil }
        XCTAssertNil(viewModel.activeRunningSession)
    }
}
