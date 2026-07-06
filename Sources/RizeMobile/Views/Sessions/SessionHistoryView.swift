import SwiftUI

/// Lists today's Tier C sessions (running, completed, and abandoned), with
/// swipe-to-delete and a minimal tap-to-edit-note affordance.
///
/// Per [[architecture-mobile.md]] §6, this list is Tier C data only — it
/// never blends in Tier B usage totals, so no provenance labeling is needed
/// here (that requirement applies to blended reports, not this single-tier
/// list).
struct SessionHistoryView: View {
    var viewModel: SessionHistoryViewModel

    @State private var editingSession: EditingSession?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if viewModel.sessions.isEmpty {
                Text("No sessions today yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.sessions, id: \.id) { session in
                    SessionRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingSession = EditingSession(session: session)
                        }
                }
                .onDelete(perform: delete)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Today's Sessions")
        .task {
            try? await viewModel.refresh()
        }
        .refreshable {
            try? await viewModel.refresh()
        }
        .sheet(item: $editingSession) { editing in
            EditSessionNoteSheet(
                session: editing.session,
                onSave: { newNote in save(sessionId: editing.session.id, note: newNote) }
            )
        }
    }

    private func delete(at offsets: IndexSet) {
        let idsToDelete = offsets.map { viewModel.sessions[$0].id }
        Task {
            do {
                for id in idsToDelete {
                    try await viewModel.deleteSession(id: id)
                }
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't delete the session. Please try again."
            }
        }
    }

    private func save(sessionId: UUID, note: String?) {
        Task {
            do {
                try await viewModel.editSession(id: sessionId, projectId: nil, note: .some(note))
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't save the session. Please try again."
            }
        }
    }
}

/// `FocusSessionRecord` isn't `Identifiable`, so this local wrapper drives
/// `.sheet(item:)` without adding a conformance to the local-store model.
///
/// Internal (rather than `private`) so RIZ-66's coverage work can construct
/// `SessionRow`/`EditSessionNoteSheet` directly in tests, matching this
/// repo's convention for `DashboardSessionRow`/`DashboardEmptyStateView`
/// (small view components are independently testable rather than only
/// reachable through their parent's `body`).
struct EditingSession: Identifiable {
    var session: FocusSessionRecord
    var id: UUID {
        session.id
    }
}

/// A minimal sheet for editing a session's note. Project/tag fields are left
/// alone, per the Tier C edit scope for this view.
struct EditSessionNoteSheet: View {
    let session: FocusSessionRecord
    let onSave: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String

    init(session: FocusSessionRecord, onSave: @escaping (String?) -> Void) {
        self.session = session
        self.onSave = onSave
        _note = State(initialValue: session.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $note)
            }
            .navigationTitle("Edit Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SessionRow: View {
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
