import Foundation
@testable import RizeMobile

/// A deterministic, manually-advanced `Clock` for tests, so session
/// lifecycle and "today" boundary behavior can be exercised without relying
/// on the wall clock or `sleep`.
final class TestClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date = Date(timeIntervalSince1970: 1_735_689_600)) { // 2025-01-01T00:00:00Z
        current = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    func set(_ date: Date) {
        lock.lock()
        current = date
        lock.unlock()
    }
}
