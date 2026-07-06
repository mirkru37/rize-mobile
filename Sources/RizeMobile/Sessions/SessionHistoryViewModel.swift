import Foundation
import Observation

/// Drives the "today's sessions" history list: fetches today's Tier C
/// sessions from `LocalStoring` and applies post-completion edits/deletes.
///
/// Per [[sync-protocol]] §Entity Classes, `focus_sessions` is mutable/LWW, so
/// edits after completion are ordinary writes that bump `updatedAt` — no
/// special-cased "edit window" logic is needed here; `LocalStoring.editSession`
/// already does the bumping.
@MainActor
@Observable
public final class SessionHistoryViewModel {
    public private(set) var sessions: [FocusSessionRecord] = []

    private let store: LocalStoring

    public init(store: LocalStoring) {
        self.store = store
    }

    /// Reloads today's non-tombstoned sessions, most recent first.
    public func refresh() async throws {
        let today = try await store.fetchTodayData()
        sessions = today.sessions.sorted { $0.startedAt > $1.startedAt }
    }

    /// Edits a session's project/note and reloads the list to reflect it.
    public func editSession(id: UUID, projectId: UUID??, note: String??) async throws {
        _ = try await store.editSession(id: id, projectId: projectId, note: note)
        try await refresh()
    }

    /// Tombstones a session and reloads the list to reflect it.
    public func deleteSession(id: UUID) async throws {
        _ = try await store.deleteSession(id: id)
        try await refresh()
    }
}
