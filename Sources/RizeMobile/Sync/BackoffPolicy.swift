import Foundation

/// Computes the delay before a retry attempt, given how many attempts have
/// already failed. `attempt` is 0 for the delay before the *first* retry
/// (i.e. after exactly one failure).
public protocol BackoffPolicy: Sendable {
    func delay(forAttempt attempt: Int) -> TimeInterval
}

/// Exponential backoff, bounded by `maxDelay` so a flaky backend can never
/// push a client into an effectively-unbounded wait.
public struct ExponentialBackoff: BackoffPolicy {
    public var baseDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval

    public init(baseDelay: TimeInterval = 1, multiplier: Double = 2, maxDelay: TimeInterval = 60) {
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
    }

    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let uncapped = baseDelay * pow(multiplier, Double(max(0, attempt)))
        return min(maxDelay, uncapped)
    }
}

/// Abstraction over "suspend for this long", so retry loops are drivable by
/// a deterministic fake in tests instead of a real `Task.sleep`. Mirrors the
/// `Clock` seam already used elsewhere in this codebase for time-dependent
/// logic.
public protocol AsyncSleeping: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

/// The real, `Task.sleep`-backed implementation used in production.
public struct TaskSleeper: AsyncSleeping {
    public init() {}

    public func sleep(seconds: TimeInterval) async throws {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}
