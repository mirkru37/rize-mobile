import SwiftUI

/// The app's top-level tab shell, hosting the dashboard and the Tier C
/// sessions screen side by side, both driven by collaborators built once by
/// `AppEnvironment` at launch.
struct RootView: View {
    var environment: AppEnvironment

    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
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
    }
}

#Preview {
    RootView(environment: .inMemory())
}
