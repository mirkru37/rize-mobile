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
    ///
    /// `onError` is invoked if the underlying observation itself fails (e.g.
    /// the tracked query errors out) — this is distinct from there simply
    /// being no data yet, and callers should surface it as a degraded-state
    /// signal rather than silently dropping it.
    func observeTodayData(
        onChange: @escaping @Sendable (TodayData) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> any ObservationToken
}
