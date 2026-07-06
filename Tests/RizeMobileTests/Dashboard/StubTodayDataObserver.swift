import Foundation
@testable import RizeMobile

/// A `TodayDataObserving` stub that lets tests push new `TodayData`
/// snapshots synchronously, without any GRDB dependency — exactly the seam
/// `DashboardViewModel` is designed around, per this ticket's requirement to
/// test view-model reactivity with a stub rather than a live database.
final class StubTodayDataObserver: TodayDataObserving, @unchecked Sendable {
    private(set) var current: TodayData
    private(set) var observeCallCount = 0
    private var onChange: (@Sendable (TodayData) -> Void)?

    init(initial: TodayData = TodayData()) {
        current = initial
    }

    func observeTodayData(onChange: @escaping @Sendable (TodayData) -> Void) -> any ObservationToken {
        observeCallCount += 1
        self.onChange = onChange
        onChange(current)
        return NoopObservationToken()
    }

    /// Simulates the underlying store changing, the way a real GRDB
    /// `ValueObservation` would report it.
    func emit(_ data: TodayData) {
        current = data
        onChange?(data)
    }
}

private final class NoopObservationToken: ObservationToken, @unchecked Sendable {
    func cancel() {}
}
