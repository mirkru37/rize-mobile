import SwiftUI

/// The dashboard's running-session banner: tier badge, elapsed wall-clock
/// time, and a quick Stop action.
///
/// Stopping reuses `SessionEngine.stop(completed:)` — this view never talks
/// to `LocalStoring` directly, matching `RunningSessionView`'s convention.
///
/// Per the same honesty-parity decision as `RunningSessionView`, the primary
/// figure is the wall-clock span (includes any paused time) and a caption
/// discloses that; the pause-excluding "active" time from
/// `SessionEngine.elapsed(now:)` is shown as a secondary line, matching
/// `RunningSessionView`'s layout.
struct DashboardRunningSessionBanner: View {
    var engine: SessionEngine
    var session: FocusSessionRecord
    var now: Date

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.kind.tierBadge)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
                Text(session.kind.displayName)
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(
                        DashboardViewModel
                            .formattedDuration(DashboardViewModel.wallClockDuration(of: session, now: now))
                    )
                    .font(.system(.body, design: .monospaced))
                    Text("Active (excl. pauses): \(DashboardViewModel.formattedDuration(engine.elapsed(now: now)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Recorded duration includes any paused time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Stop", role: .destructive) {
                stop()
            }
            .disabled(engine.isMutating)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func stop() {
        Task {
            do {
                _ = try await engine.stop(completed: true)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't stop the session. Please try again."
            }
        }
    }
}
