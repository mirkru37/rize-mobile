import Foundation
@testable import RizeMobile

/// A no-op `AsyncSleeping` fake that records every requested duration
/// instead of actually suspending, so backoff tests are instant and
/// deterministic rather than bound by real wall-clock waits.
final class FakeSleeper: AsyncSleeping, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requestedDurations: [TimeInterval] = []

    func sleep(seconds: TimeInterval) async throws {
        lock.lock()
        requestedDurations.append(seconds)
        lock.unlock()
    }
}
