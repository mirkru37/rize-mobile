import Foundation

/// A live handle to an active `TodayDataObserving` subscription. Calling
/// `cancel()` stops further updates; safe to call more than once.
public protocol ObservationToken: Sendable {
    func cancel()
}

/// Seam over GRDB's `ValueObservation` for "today"'s blended Tier B/C data,
/// so view models (e.g. `DashboardViewModel`) depend on a small protocol
/// instead of GRDB directly, and are testable with a stub rather than a live
/// database, per this repo's MVVM convention.
public protocol TodayDataObserving: Sendable {
    /// Starts observing `TodayData`. `onChange` is invoked once immediately
    /// with the current value, and again whenever the underlying data
    /// changes, until the returned token is cancelled (or, for GRDB-backed
    /// implementations, deallocated).
    func observeTodayData(onChange: @escaping @Sendable (TodayData) -> Void) -> any ObservationToken
}
