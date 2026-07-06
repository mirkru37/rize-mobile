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

        let token = observer.observeTodayData { data in
            received.append(data)
        }
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

        let token = observer.observeTodayData { data in
            received.append(data)
        }
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

    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        while !condition() {
            await Task.yield()
        }
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
