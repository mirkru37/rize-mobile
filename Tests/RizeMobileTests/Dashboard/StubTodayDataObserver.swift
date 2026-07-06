import Foundation
@testable import RizeMobile

/// A `TodayDataObserving` stub that lets tests push new `TodayData`
/// snapshots (and simulated observation failures) synchronously, without
/// any GRDB dependency — exactly the seam `DashboardViewModel` is designed
/// around, per this ticket's requirement to test view-model reactivity with
/// a stub rather than a live database.
///
/// The returned token actually detaches `onChange`/`onError` on `cancel()`,
/// mirroring `GRDBCancellableToken`'s real behavior, so tests can assert
/// that a view model stops reacting after it tears down its observation.
final class StubTodayDataObserver: TodayDataObserving, @unchecked Sendable {
    private(set) var current: TodayData
    private(set) var observeCallCount = 0
    private var onChange: (@Sendable (TodayData) -> Void)?
    private var onError: (@Sendable (Error) -> Void)?

    init(initial: TodayData = TodayData()) {
        current = initial
    }

    func observeTodayData(
        onChange: @escaping @Sendable (TodayData) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> any ObservationToken {
        observeCallCount += 1
        self.onChange = onChange
        self.onError = onError
        onChange(current)
        return StubObservationToken { [weak self] in
            self?.onChange = nil
            self?.onError = nil
        }
    }

    /// Simulates the underlying store changing, the way a real GRDB
    /// `ValueObservation` would report it. A no-op once the returned token
    /// has been cancelled.
    func emit(_ data: TodayData) {
        current = data
        onChange?(data)
    }

    /// Simulates the underlying observation itself failing, the way a real
    /// GRDB `ValueObservation` would report a query error. A no-op once the
    /// returned token has been cancelled.
    func emitError(_ error: Error) {
        onError?(error)
    }
}

/// A stub `ObservationToken` that runs `onCancel` (at most once) when
/// cancelled, so `StubTodayDataObserver` can actually stop delivering
/// updates after cancellation instead of silently ignoring it.
private final class StubObservationToken: ObservationToken, @unchecked Sendable {
    private let onCancel: () -> Void
    private var isCancelled = false

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}
