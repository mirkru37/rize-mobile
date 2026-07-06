import Foundation

/// Pure, testable elapsed-time bookkeeping for a running or paused Tier C
/// session, independent of the `LocalStoring` persistence layer.
///
/// Pause/resume is **not** part of the synced `focus_sessions` entity per
/// [[sync-protocol]] (its wire shape carries only `started_at`/`ended_at`),
/// so this state is a client-only concept: it exists purely to compute
/// correct elapsed time across pauses, and is persisted separately (see
/// `SessionClockStoring`) rather than through `LocalStoring`.
public struct SessionClockState: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var accumulatedPauseS: TimeInterval
    public var pausedAt: Date?

    public init(startedAt: Date, accumulatedPauseS: TimeInterval = 0, pausedAt: Date? = nil) {
        self.startedAt = startedAt
        self.accumulatedPauseS = accumulatedPauseS
        self.pausedAt = pausedAt
    }

    /// Elapsed active time as of `now`. While paused, elapsed time is frozen
    /// at the instant the pause began.
    public func elapsed(now: Date) -> TimeInterval {
        let referenceDate = pausedAt ?? now
        return max(0, referenceDate.timeIntervalSince(startedAt) - accumulatedPauseS)
    }

    /// Begins a pause at `date`. A no-op if already paused.
    public mutating func pause(at date: Date) {
        guard pausedAt == nil else { return }
        pausedAt = date
    }

    /// Ends a pause at `date`, folding the paused interval into the running
    /// accumulated total. A no-op if not currently paused.
    public mutating func resume(at date: Date) {
        guard let pausedAt else { return }
        accumulatedPauseS += date.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }
}
