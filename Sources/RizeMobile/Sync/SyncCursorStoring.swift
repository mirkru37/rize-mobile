import Foundation

/// Persists the opaque pull cursor from [[sync-protocol]] §Pull
/// (`GET /v1/sync/changes?cursor=...`) across sync cycles and app relaunches.
///
/// [[sync-protocol]]'s critical invariant is that applying a pulled page and
/// persisting the new cursor happen in the same local database transaction,
/// so a crash between the two can never apply data and lose the cursor
/// advance. This client stores the cursor outside the GRDB local store
/// (`UserDefaults`, like `SessionClockStoring`) rather than inside it, which
/// relaxes that atomicity guarantee slightly: a crash between applying a page
/// and saving its cursor here would cause the same page to be re-fetched and
/// re-applied on the next pull. Per [[sync-protocol]] §Pull, "pulls are
/// idempotent and safe to repeat" — re-applying an already-known page is a
/// harmless no-op — so this is a deliberate, documented simplification rather
/// than a silent violation of the doc's safety property, not a strict
/// same-transaction guarantee. See the RIZ-46 PR for the full rationale.
public protocol SyncCursorStoring: Sendable {
    func loadCursor() -> String?
    func saveCursor(_ cursor: String?)
}

/// `UserDefaults`-backed `SyncCursorStoring`.
public final class UserDefaultsSyncCursorStore: SyncCursorStoring, @unchecked Sendable {
    private static let cursorKey = "com.rizeclone.mobile.sync.cursor"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadCursor() -> String? {
        defaults.string(forKey: Self.cursorKey)
    }

    public func saveCursor(_ cursor: String?) {
        if let cursor {
            defaults.set(cursor, forKey: Self.cursorKey)
        } else {
            defaults.removeObject(forKey: Self.cursorKey)
        }
    }
}
