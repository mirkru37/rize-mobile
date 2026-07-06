import Foundation
@testable import RizeMobile

/// An in-memory `SessionClockStoring` fake, so `SessionEngine` tests never
/// touch real `UserDefaults` and each test starts from a clean slate.
final class InMemorySessionClockStore: SessionClockStoring, @unchecked Sendable {
    private var stored: (sessionId: UUID, state: SessionClockState)?

    func load(sessionId: UUID) -> SessionClockState? {
        guard let stored, stored.sessionId == sessionId else { return nil }
        return stored.state
    }

    func save(_ state: SessionClockState, sessionId: UUID) {
        stored = (sessionId, state)
    }

    func clear() {
        stored = nil
    }
}
