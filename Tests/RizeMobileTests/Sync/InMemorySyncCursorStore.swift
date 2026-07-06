import Foundation
@testable import RizeMobile

/// An in-memory `SyncCursorStoring` fake, so cursor-persistence tests never
/// touch real `UserDefaults`.
final class InMemorySyncCursorStore: SyncCursorStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var cursor: String?

    func loadCursor() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cursor
    }

    func saveCursor(_ cursor: String?) {
        lock.lock()
        defer { lock.unlock() }
        self.cursor = cursor
    }
}
