import XCTest
@testable import RizeMobile

/// `loadError` surfacing (RIZ-45 M4) and observation-lifecycle (RIZ-45 M5)
/// tests for `DashboardViewModel`. Split out of `DashboardViewModelTests`
/// purely to stay under SwiftLint's file/type length limits, matching
/// `SessionEngineRecoveryTests`'s precedent — no behavioral difference from
/// being one file.
@MainActor
final class DashboardViewModelReliabilityTests: XCTestCase {
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
    /// `DashboardViewModelTests`'s pattern for deterministically awaiting an
    /// async effect without a fixed `sleep` — but bounded by `timeout`, so a
    /// condition that (due to a bug) never becomes true fails the test
    /// instead of hanging it indefinitely (RIZ-45 CI hang fix).
    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("Timed out after \(timeout)s waiting for condition", file: file, line: line)
                return
            }
            await Task.yield()
        }
    }

    // MARK: loadError (M4)

    func testLoadErrorIsSetWhenTheObservationItselfFails() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)

        viewModel.start()
        observer.emitError(StubError())

        try await waitUntil { viewModel.loadError != nil }
        XCTAssertEqual(viewModel.loadError, .todayDataObservationFailed)
    }

    func testLoadErrorIsSetWhenFetchingTheActiveRunningSessionFails() async throws {
        let store = try makeStore()
        let failingStore = FailingFetchActiveRunningSessionStore(wrapping: store)
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: failingStore, observer: observer)

        viewModel.start()
        observer.emit(TodayData())

        try await waitUntil { viewModel.loadError != nil }
        XCTAssertEqual(viewModel.loadError, .activeRunningSessionFetchFailed)
        // A fetch failure is distinct from "nothing is running": the latter
        // is simply `activeRunningSession == nil` without a `loadError`.
        XCTAssertNil(viewModel.activeRunningSession)
    }

    func testLoadErrorIsClearedAfterASubsequentSuccessfulObservation() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        viewModel.start()
        observer.emitError(StubError())
        try await waitUntil { viewModel.loadError != nil }

        observer.emit(TodayData())
        try await waitUntil { viewModel.loadError == nil }

        XCTAssertNil(viewModel.loadError)
    }

    // MARK: observation lifecycle (M5)

    func testStopCancelsTheObservationSoFurtherEmissionsDoNotApply() async throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        let now = Date(timeIntervalSince1970: 10000)
        let before = makeSession(startedAt: now.addingTimeInterval(-600), endedAt: now.addingTimeInterval(-300))
        let after = makeSession(startedAt: now.addingTimeInterval(-120), endedAt: now.addingTimeInterval(-60))
        viewModel.start()
        observer.emit(TodayData(sessions: [before]))
        try await waitUntil { viewModel.sessions.count == 1 }

        viewModel.stop()
        observer.emit(TodayData(sessions: [before, after]))
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        // The observation was cancelled before the second emission, so it
        // must never be applied — the view model keeps its last-known state.
        XCTAssertEqual(viewModel.sessions.map(\.id), [before.id])
    }

    func testStopIsSafeToCallMoreThanOnce() throws {
        let store = try makeStore()
        let observer = StubTodayDataObserver()
        let viewModel = DashboardViewModel(store: store, observer: observer)
        viewModel.start()

        viewModel.stop()
        viewModel.stop()
    }
}

private struct StubError: Error, Equatable {}

/// A `LocalStoring` decorator that always fails `fetchActiveRunningSession`,
/// delegating everything else to the wrapped store — used to exercise
/// `DashboardViewModel`'s `loadError` surfacing without a dedicated
/// full-protocol fake.
private struct FailingFetchActiveRunningSessionStore: LocalStoring {
    private let wrapped: LocalStoring

    init(wrapping wrapped: LocalStoring) {
        self.wrapped = wrapped
    }

    func startSession(
        kind: FocusSessionKind,
        projectId: UUID?,
        plannedDurationS: Int?,
        note: String?
    ) async throws -> FocusSessionRecord {
        try await wrapped.startSession(
            kind: kind,
            projectId: projectId,
            plannedDurationS: plannedDurationS,
            note: note
        )
    }

    func stopSession(id: UUID, status: FocusSessionStatus) async throws -> FocusSessionRecord {
        try await wrapped.stopSession(id: id, status: status)
    }

    func editSession(id: UUID, projectId: UUID??, note: String??) async throws -> FocusSessionRecord {
        try await wrapped.editSession(id: id, projectId: projectId, note: note)
    }

    func deleteSession(id: UUID) async throws -> FocusSessionRecord {
        try await wrapped.deleteSession(id: id)
    }

    func recordApproximateEvent(
        startedAt: Date,
        endedAt: Date,
        appBundleId: String?,
        categoryId: UUID?,
        projectId: UUID?
    ) async throws -> ActivityEventRecord {
        try await wrapped.recordApproximateEvent(
            startedAt: startedAt,
            endedAt: endedAt,
            appBundleId: appBundleId,
            categoryId: categoryId,
            projectId: projectId
        )
    }

    func fetchTodayData() async throws -> TodayData {
        try await wrapped.fetchTodayData()
    }

    func fetchActiveRunningSession() async throws -> FocusSessionRecord? {
        throw StubError()
    }

    func fetchUnsyncedBatch(limit: Int) async throws -> UnsyncedBatch {
        try await wrapped.fetchUnsyncedBatch(limit: limit)
    }

    func markSynced(eventIds: [UUID], sessionIds: [UUID]) async throws {
        try await wrapped.markSynced(eventIds: eventIds, sessionIds: sessionIds)
    }
}
