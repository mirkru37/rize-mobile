import Foundation
import GRDB

/// GRDB `ValueObservation`-backed `TodayDataObserving`.
///
/// Deliberately re-runs the same day-scoped query as
/// `GRDBLocalStore.fetchTodayData()` rather than calling that async method,
/// since `ValueObservation.tracking` needs a synchronous closure over a
/// `Database` to know which tables to watch. The query itself is kept in
/// lockstep with `fetchTodayData()` by inspection; both filter
/// non-tombstoned rows to the calendar day containing "now".
public final class GRDBTodayDataObserver: TodayDataObserving {
    private let database: AppDatabase
    private let calendar: Calendar
    private let clock: Clock

    public init(database: AppDatabase, calendar: Calendar = .current, clock: Clock = SystemClock()) {
        self.database = database
        self.calendar = calendar
        self.clock = clock
    }

    public func observeTodayData(onChange: @escaping @Sendable (TodayData) -> Void) -> any ObservationToken {
        let calendar = calendar
        let clock = clock
        let observation = ValueObservation.tracking { db in
            try Self.fetchTodayData(db, calendar: calendar, now: clock.now())
        }
        let cancellable = observation.start(
            in: database.dbWriter,
            onError: { _ in },
            onChange: onChange
        )
        return GRDBCancellableToken(cancellable: cancellable)
    }

    private static func fetchTodayData(_ db: Database, calendar: Calendar, now: Date) throws -> TodayData {
        let dayInterval = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 0)

        let events = try ActivityEventRecord
            .filter(Column("deleted") == false)
            .filter(Column("startedAt") >= dayInterval.start && Column("startedAt") < dayInterval.end)
            .order(Column("startedAt"))
            .fetchAll(db)

        let sessions = try FocusSessionRecord
            .filter(Column("deletedAt") == nil)
            .filter(Column("startedAt") >= dayInterval.start && Column("startedAt") < dayInterval.end)
            .order(Column("startedAt"))
            .fetchAll(db)

        return TodayData(events: events, sessions: sessions)
    }
}

/// Wraps GRDB's `DatabaseCancellable` behind `ObservationToken`, so the
/// protocol seam itself carries no GRDB types.
private final class GRDBCancellableToken: ObservationToken, @unchecked Sendable {
    private let cancellable: DatabaseCancellable

    init(cancellable: DatabaseCancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        cancellable.cancel()
    }
}
