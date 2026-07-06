import XCTest
@testable import RizeMobile

final class GRDBTodayDataObserverTests: XCTestCase {
    func testObserveTodayDataDeliversTheInitialValueAndSubsequentChanges() async throws {
        let clock = TestClock()
        let database = try AppDatabase.inMemory()
        let store = GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: clock,
            uuidGenerator: UUIDv7Generator(clock: clock)
        )
        let observer = GRDBTodayDataObserver(database: database, clock: clock)
        let received = ReceivedValues()

        let token = observer.observeTodayData(
            onChange: { data in received.append(data) },
            onError: { _ in }
        )
        defer { token.cancel() }

        try await waitUntil { received.count >= 1 }
        XCTAssertEqual(received.values.first?.sessions.count, 0)

        _ = try await store.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)

        try await waitUntil { (received.values.last?.sessions.count ?? 0) == 1 }
    }

    func testObserveTodayDataExcludesRowsOutsideTheCurrentCalendarDay() async throws {
        // Two independent clocks (rather than one shared, mutable clock) so
        // the observer's notion of "today" stays fixed while a session is
        // inserted with a `startedAt` from a different calendar day.
        let todayClock = TestClock(Date(timeIntervalSince1970: 1_735_732_800)) // 2025-01-01T12:00:00Z
        let yesterdayClock = TestClock(todayClock.now().addingTimeInterval(-86400))
        let database = try AppDatabase.inMemory()
        let todayStore = GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: todayClock,
            uuidGenerator: UUIDv7Generator(clock: todayClock)
        )
        let yesterdayStore = GRDBLocalStore(
            database: database,
            deviceId: "test-device",
            clock: yesterdayClock,
            uuidGenerator: UUIDv7Generator(clock: yesterdayClock)
        )
        let observer = GRDBTodayDataObserver(database: database, clock: todayClock)
        let received = ReceivedValues()

        let token = observer.observeTodayData(
            onChange: { data in received.append(data) },
            onError: { _ in }
        )
        defer { token.cancel() }
        try await waitUntil { received.count >= 1 }
        XCTAssertEqual(received.values.first?.sessions.count, 0)

        _ = try await yesterdayStore.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)

        // Give the observation a chance to re-run after the write; a session
        // outside today's window must never be picked up.
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertEqual(received.values.last?.sessions.count, 0)

        _ = try await todayStore.startSession(kind: .focus, projectId: nil, plannedDurationS: nil, note: nil)
        try await waitUntil { (received.values.last?.sessions.count ?? 0) == 1 }
    }

    func testObserveTodayDataInvokesOnErrorWhenTheTrackedQueryFails() async throws {
        let clock = TestClock()
        let database = try AppDatabase.inMemory()
        let observer = GRDBTodayDataObserver(database: database, clock: clock)
        let received = ReceivedValues()
        let receivedErrors = ReceivedErrors()

        let token = observer.observeTodayData(
            onChange: { data in received.append(data) },
            onError: { error in receivedErrors.append(error) }
        )
        defer { token.cancel() }
        try await waitUntil { received.count >= 1 }

        // Force the tracked query to fail on its next run by inserting a row
        // with an invalid `id` — `FocusSessionRecord.init(row:)` throws for
        // that (see the model's hand-written `FetchableRecord` conformance),
        // so re-running `fetchTodayData` after this write fails decoding.
        //
        // This is a genuine INSERT (a data change, not a schema change like
        // `DROP TABLE`), so it reliably fires GRDB's change-tracking hook and
        // triggers a re-run of the tracked query — a schema-level change
        // isn't guaranteed to do so, which previously left this test's
        // `waitUntil` spinning forever (RIZ-45 CI hang fix).
        try await database.dbWriter.write { db in
            try db.execute(
                sql: """
                INSERT INTO focusSessions (id, deviceId, kind, startedAt, status, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: ["not-a-uuid", "test-device", "focus", clock.now(), "running", clock.now(), clock.now()]
            )
        }

        try await waitUntil { receivedErrors.count >= 1 }
        XCTAssertGreaterThanOrEqual(receivedErrors.count, 1)
    }

    /// Polls `condition` until it's true, yielding between checks, matching
    /// `DashboardViewModelTests`'s pattern for deterministically awaiting an
    /// async effect without a fixed `sleep` — but bounded by `timeout`, so a
    /// condition that (due to a bug) never becomes true fails the test
    /// instead of hanging it indefinitely.
    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @Sendable () -> Bool
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
}

/// Thread-safe accumulator for errors delivered by a `ValueObservation`'s
/// `onError`, mirroring `ReceivedValues`.
private final class ReceivedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storedErrors: [Error] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedErrors.count
    }

    func append(_ error: Error) {
        lock.lock()
        storedErrors.append(error)
        lock.unlock()
    }
}

/// Thread-safe accumulator for values delivered by a `ValueObservation`
/// callback, since GRDB may deliver on a queue other than the test's.
private final class ReceivedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [TodayData] = []

    var values: [TodayData] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValues.count
    }

    func append(_ value: TodayData) {
        lock.lock()
        storedValues.append(value)
        lock.unlock()
    }
}
