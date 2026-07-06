import SwiftUI

/// Shown when there are no sessions today and none currently running: guides
/// the user to the Sessions tab to start one.
///
/// Copy deliberately avoids implying any automatic tracking is happening,
/// consistent with `StartSessionView`'s honesty-requirement footer — this
/// app only ever has data here because the user explicitly started a
/// session.
struct DashboardEmptyStateView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No sessions yet today")
                .font(.title2.bold())
            Text(
                "Manual timers and focus sessions you start will show up here " +
                    "— this app does not automatically track all iOS activity."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
            Button("Start a Session") {
                selectedTab = .sessions
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DashboardEmptyStateView(selectedTab: .constant(.dashboard))
}
