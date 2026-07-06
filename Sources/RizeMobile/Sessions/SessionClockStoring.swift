import Foundation

/// Persists the client-only `SessionClockState` for the currently active
/// session, so pause/resume state (and the fact that a session is running at
/// all, ahead of an authoritative re-check against `LocalStoring`) survives
/// an app relaunch.
///
/// Deliberately separate from `LocalStoring`/`GRDBLocalStore`: this state has
/// no wire representation (see `SessionClockState`) and does not belong in
/// the synced local store's schema.
public protocol SessionClockStoring: Sendable {
    /// Loads the persisted clock state, if it belongs to `sessionId`. Returns
    /// `nil` if nothing is persisted, or if the persisted state belongs to a
    /// different session (e.g. a stale value from a previously stopped one).
    func load(sessionId: UUID) -> SessionClockState?

    /// Persists `state` as belonging to `sessionId`, replacing any previous
    /// value.
    func save(_ state: SessionClockState, sessionId: UUID)

    /// Removes any persisted clock state.
    func clear()
}

/// `UserDefaults`-backed `SessionClockStoring`. Suitable for production use:
/// this data is local-only view state, never synced and never read by an
/// extension target, so it does not need the App Group container or the
/// GRDB local store's on-disk file protection.
public final class UserDefaultsSessionClockStore: SessionClockStoring, @unchecked Sendable {
    private static let sessionIdKey = "com.rizeclone.mobile.sessionClock.sessionId"
    private static let stateKey = "com.rizeclone.mobile.sessionClock.state"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(sessionId: UUID) -> SessionClockState? {
        guard defaults.string(forKey: Self.sessionIdKey) == sessionId.uuidString,
              let data = defaults.data(forKey: Self.stateKey)
        else {
            return nil
        }
        return try? JSONDecoder().decode(SessionClockState.self, from: data)
    }

    public func save(_ state: SessionClockState, sessionId: UUID) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(sessionId.uuidString, forKey: Self.sessionIdKey)
        defaults.set(data, forKey: Self.stateKey)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.sessionIdKey)
        defaults.removeObject(forKey: Self.stateKey)
    }
}
