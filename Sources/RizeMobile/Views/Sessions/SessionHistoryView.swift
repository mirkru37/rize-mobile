import SwiftUI

/// Lists today's Tier C sessions (running, completed, and abandoned).
///
/// Per [[architecture-mobile.md]] §6, this list is Tier C data only — it
/// never blends in Tier B usage totals, so no provenance labeling is needed
/// here (that requirement applies to blended reports, not this single-tier
/// list).
struct SessionHistoryView: View {
    var viewModel: SessionHistoryViewModel

    var body: some View {
        List {
            if viewModel.sessions.isEmpty {
                Text("No sessions today yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.sessions, id: \.id) { session in
                    SessionRow(session: session)
                }
            }
        }
        .navigationTitle("Today's Sessions")
        .task {
            try? await viewModel.refresh()
        }
        .refreshable {
            try? await viewModel.refresh()
        }
    }
}

private struct SessionRow: View {
    let session: FocusSessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.kind.displayName)
                    .font(.body)
                Spacer()
                Text(session.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let note = session.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
