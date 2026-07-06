import SwiftUI

/// Placeholder dashboard shown until Screen Time tracking lands.
///
/// The full three-tier tracking model (Tier A/B/C) described in
/// `documentation/architecture-mobile.md` requires the
/// `com.apple.developer.family-controls` entitlement, which is pending
/// Apple approval (RIZ-20). This view will be replaced with the real
/// dashboard once that milestone begins.
struct DashboardView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Today")
                    .font(.largeTitle)
                    .bold()
                Text("Screen Time tracking arrives in a later milestone.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Today")
        }
    }
}

#Preview {
    DashboardView()
}
