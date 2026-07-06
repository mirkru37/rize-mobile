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
struct DashboardView: View {
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
            try? await engine.recoverRunningSession()
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
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

#Preview {
    let environment = AppEnvironment.inMemory()
    return DashboardView(
        viewModel: environment.dashboardViewModel,
        engine: environment.sessionEngine,
        selectedTab: .constant(.dashboard)
    )
}
