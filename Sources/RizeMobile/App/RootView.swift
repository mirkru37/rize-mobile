import SwiftUI

/// The app's top-level tab shell, hosting the dashboard and the Tier C
/// sessions screen side by side, both driven by collaborators built once by
/// `AppEnvironment` at launch.
///
/// `AppEnvironment.live()` can fail to open/migrate the on-disk local store
/// (see `AppEnvironment.live()`); rather than crashing, that failure is
/// threaded through as a `Result` and rendered as a full-screen error state
/// here instead of the dashboard/sessions tabs.
struct RootView: View {
    var environmentResult: Result<AppEnvironment, Error>

    @State private var selectedTab: AppTab = .dashboard

    /// Convenience initializer for the common success case (previews, tests,
    /// and any caller that already has a live `AppEnvironment`).
    init(environment: AppEnvironment) {
        environmentResult = .success(environment)
    }

    init(environmentResult: Result<AppEnvironment, Error>) {
        self.environmentResult = environmentResult
    }

    var body: some View {
        switch environmentResult {
        case let .success(environment):
            TabView(selection: $selectedTab) {
                DashboardView(
                    viewModel: environment.dashboardViewModel,
                    engine: environment.sessionEngine,
                    selectedTab: $selectedTab
                )
                .tabItem { Label("Today", systemImage: "chart.bar.fill") }
                .tag(AppTab.dashboard)

                SessionsView(
                    engine: environment.sessionEngine,
                    historyViewModel: environment.historyViewModel
                )
                .tabItem { Label("Sessions", systemImage: "timer") }
                .tag(AppTab.sessions)
            }
        case let .failure(error):
            LocalStoreErrorView(error: error)
        }
    }
}

/// Shown in place of the dashboard/sessions tabs when `AppEnvironment.live()`
/// couldn't open the on-disk local store, so the user sees a clear message
/// instead of the app crashing or silently doing nothing.
private struct LocalStoreErrorView: View {
    var error: Error

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Couldn't open your data")
                .font(.title2.bold())
            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RootView(environment: .inMemory())
}

#Preview("Error state") {
    RootView(environmentResult: .failure(CocoaError(.fileWriteUnknown)))
}
