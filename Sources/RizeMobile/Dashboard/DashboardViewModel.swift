import Foundation
import Observation

/// Distinguishes an actual fetch/observation failure from the ordinary "no
/// session is currently running" state (which is simply `activeRunningSession
/// == nil`, not an error). Surfaced by `DashboardViewModel.loadError` as a
/// small non-blocking banner in `DashboardView`, since the dashboard's data
/// may still be showing a stale-but-valid snapshot.
public enum DashboardLoadError: Error, Equatable {
    /// The underlying `TodayDataObserving` subscription itself failed (e.g.
    /// the tracked query errored out).
    case todayDataObservationFailed
    /// `LocalStoring.fetchActiveRunningSession()` threw.
    case activeRunningSessionFetchFailed

    /// User-facing, non-blocking banner copy.
    public var bannerMessage: String {
        switch self {
        case .todayDataObservationFailed:
            "Couldn't refresh today's sessions. Showing the last known data."
        case .activeRunningSessionFetchFailed:
            "Couldn't check for a running session. Pull to refresh or reopen the app."
        }
    }
}

/// Drives the dashboard's "today" summary: today's Tier C sessions and the
/// currently-running session, kept live off `LocalStoring`/`TodayDataObserving`.
///
/// Reactivity: today's session list is kept live via `TodayDataObserving`'s
/// `ValueObservation`-backed seam, so this view model depends only on a
/// protocol (not GRDB directly) and is testable with a stub, per this repo's
/// MVVM convention (see `SessionEngine`/`SessionHistoryViewModel`). Elapsed
/// time for a running session is a pure function of an externally-supplied
/// "now" (`totalTrackedDuration(now:)`); the view drives that with a
/// `TimelineView` tick, matching `RunningSessionView`'s convention, rather
/// than this view model owning a timer.
@MainActor
@Observable
public final class DashboardViewModel {
    /// Today's non-tombstoned Tier C sessions, most recent first.
    public private(set) var sessions: [FocusSessionRecord] = []

    /// The currently-running session, if any, regardless of which calendar
    /// day it started on — sourced from `LocalStoring.fetchActiveRunningSession()`
    /// so a session started before midnight still drives the banner.
    public private(set) var activeRunningSession: FocusSessionRecord?

    /// Set when either the underlying `TodayDataObserving` subscription or
    /// `LocalStoring.fetchActiveRunningSession()` fails; `nil` while things
    /// are working normally (including when there's simply no running
    /// session). See `DashboardLoadError`.
    public private(set) var loadError: DashboardLoadError?

    private let store: LocalStoring
    private let observer: TodayDataObserving
    /// GRDB's underlying cancellable (see `GRDBTodayDataObserver`) stops the
    /// observation on deinit, so replacing/dropping this is enough cleanup —
    /// no explicit `deinit` is needed here (and one can't synchronously touch
    /// this `@MainActor`-isolated property from a nonisolated `deinit`).
    private var observationToken: (any ObservationToken)?

    public init(store: LocalStoring, observer: TodayDataObserving) {
        self.store = store
        self.observer = observer
    }

    /// Starts observing today's data. Call once, early in the view's
    /// lifecycle (e.g. from a `.task`). Safe to call more than once — any
    /// prior observation is cancelled first.
    public func start() {
        observationToken?.cancel()
        observationToken = observer.observeTodayData(
            onChange: { [weak self] today in
                Task { @MainActor in
                    self?.apply(today)
                }
            },
            onError: { [weak self] _ in
                Task { @MainActor in
                    self?.loadError = .todayDataObservationFailed
                }
            }
        )
    }

    /// Cancels the current observation, if any. Call when the dashboard is
    /// no longer visible (e.g. from the view's `.onDisappear`) so the
    /// underlying `ValueObservation` work — and its retention of this view
    /// model via the `onChange`/`onError` closures — doesn't keep running
    /// while the dashboard isn't on screen. Safe to call more than once, and
    /// safe to call `start()` again afterwards.
    public func stop() {
        observationToken?.cancel()
        observationToken = nil
    }

    /// Applies a fresh `TodayData` snapshot and kicks off a re-fetch of the
    /// day-agnostic active running session, since a session's status
    /// transition (running -> completed/abandoned, or a brand new start) is
    /// exactly the kind of change `TodayDataObserving` reports.
    private func apply(_ today: TodayData) {
        loadError = nil
        sessions = today.sessions.sorted { $0.startedAt > $1.startedAt }
        refreshActiveRunningSession()
    }

    private func refreshActiveRunningSession() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                activeRunningSession = try await store.fetchActiveRunningSession()
                loadError = nil
            } catch {
                loadError = .activeRunningSessionFetchFailed
            }
        }
    }

    // MARK: Aggregation

    /// Total wall-clock tracked time across today's sessions, as of `now`.
    ///
    /// Per [[architecture-mobile.md]]'s Tier C pause-semantics decision, each
    /// session's contribution is its wall-clock span and therefore
    /// **includes** any paused time — this is a real total of exact,
    /// user-timed sessions, never a fabricated "automatic" figure (per §6,
    /// the UX Honesty Requirement).
    public func totalTrackedDuration(now: Date) -> TimeInterval {
        sessions.reduce(0) { $0 + Self.wallClockDuration(of: $1, now: now) }
    }

    /// The wall-clock span of a single session as of `now`: `endedAt` if the
    /// session has already stopped, otherwise `now` for one still running.
    public static func wallClockDuration(of session: FocusSessionRecord, now: Date) -> TimeInterval {
        max(0, (session.endedAt ?? now).timeIntervalSince(session.startedAt))
    }

    /// Formats a duration as `HH:MM:SS`, matching `RunningSessionView`'s
    /// timer format.
    public static func formattedDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
