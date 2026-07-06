import os
import SwiftUI

/// Today's dashboard: total tracked time, today's Tier C sessions, and a
/// running-session banner with a quick Stop action (reusing
/// `SessionEngine.stop(completed:)` rather than reimplementing session
/// lifecycle logic).
///
/// Per [[architecture-mobile.md]] §6 (UX Honesty Requirement), every duration
/// shown here comes from exact, user-timed Tier C sessions — there is no
/// fabricated Tier A/B-derived "automatic" total, and each session carries
/// its tier badge (`FocusSessionKind.tierBadge`, "Focus" vs "Manual"). Per
/// the Tier C pause-semantics decision, all durations are wall-clock spans
/// that include any paused time.
///
/// Observation lifecycle: `viewModel.start()` is called from `.task` (once
/// per appearance) and `viewModel.stop()` from `.onDisappear`, so the
/// underlying `ValueObservation` isn't kept running while this screen isn't
/// visible.
struct DashboardView: View {
    private static let logger = Logger(subsystem: "com.rizeclone.mobile", category: "DashboardView")

    var viewModel: DashboardViewModel
    var engine: SessionEngine
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
            .navigationTitle("Today")
        }
        .task {
            viewModel.start()
            do {
                try await engine.recoverRunningSession()
            } catch {
                // Non-blocking: recovery failing just means an in-flight
                // session (if any) isn't restored this launch, but it's
                // still logged rather than silently swallowed.
                Self.logger.error("recoverRunningSession failed: \(String(describing: error), privacy: .public)")
            }
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 0) {
            if let loadError = viewModel.loadError {
                DashboardLoadErrorBanner(loadError: loadError)
            }
            if viewModel.sessions.isEmpty, viewModel.activeRunningSession == nil {
                DashboardEmptyStateView(selectedTab: $selectedTab)
            } else {
                List {
                    if let activeRunningSession = viewModel.activeRunningSession {
                        Section {
                            DashboardRunningSessionBanner(engine: engine, session: activeRunningSession, now: now)
                        }
                    }
                    Section("Total tracked today") {
                        Text(DashboardViewModel.formattedDuration(viewModel.totalTrackedDuration(now: now)))
                            .font(.system(size: 34, weight: .semibold, design: .monospaced))
                        Text("Exact — timed manually, not inferred from device activity.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    historySection(now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func historySection(now: Date) -> some View {
        let historicalSessions = viewModel.sessions.filter { $0.id != viewModel.activeRunningSession?.id }
        if !historicalSessions.isEmpty {
            Section("Sessions") {
                ForEach(historicalSessions, id: \.id) { session in
                    DashboardSessionRow(session: session, now: now)
                }
            }
        }
    }
}

/// A small, non-blocking banner shown above the dashboard's content when
/// `DashboardViewModel.loadError` is set — the rest of the screen keeps
/// showing whatever data it already has.
private struct DashboardLoadErrorBanner: View {
    var loadError: DashboardLoadError

    var body: some View {
        Text(loadError.bannerMessage)
            .font(.caption)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.15))
    }
}

#Preview {
    let environment = AppEnvironment.inMemory()
    return DashboardView(
        viewModel: environment.dashboardViewModel,
        engine: environment.sessionEngine,
        selectedTab: .constant(.dashboard)
    )
}
