import SwiftUI

/// A single row in the dashboard's today session list: tier badge, kind,
/// time range, and wall-clock duration (including any paused time, per
/// [[architecture-mobile.md]]'s Tier C pause-semantics decision).
struct DashboardSessionRow: View {
    var session: FocusSessionRecord
    var now: Date

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.kind.tierBadge)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(session.kind.displayName)
                        .font(.body)
                }
                Text(timeRangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(DashboardViewModel.formattedDuration(DashboardViewModel.wallClockDuration(of: session, now: now)))
                .font(.system(.body, design: .monospaced))
        }
    }

    private var timeRangeText: String {
        let start = Self.timeFormatter.string(from: session.startedAt)
        guard let endedAt = session.endedAt else {
            return "\(start) – now"
        }
        return "\(start) – \(Self.timeFormatter.string(from: endedAt))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
