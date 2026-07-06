import Foundation

/// Abstraction over "now" so time-dependent code (session lifecycle, "today"
/// windows, sync bookkeeping timestamps) can be driven by a deterministic,
/// injected clock in tests instead of the wall clock.
public protocol Clock: Sendable {
    func now() -> Date
}

/// The real, wall-clock-backed implementation used in production.
public struct SystemClock: Clock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}
