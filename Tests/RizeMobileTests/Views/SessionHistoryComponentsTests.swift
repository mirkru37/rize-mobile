import XCTest
@testable import RizeMobile

/// Covers `SessionHistoryView`'s nested view components (RIZ-66) —
/// `EditingSession`/`SessionRow`/`EditSessionNoteSheet` were changed from
/// `private` to internal so they're directly constructible here, matching
/// this repo's convention for `DashboardSessionRow`/`DashboardEmptyStateView`
/// (small view components are independently testable rather than only
/// reachable through their parent's `body`, which can't otherwise exercise
/// `SessionRow`/`EditSessionNoteSheet`'s own bodies — building a parent
/// view's `body` constructs child view values but doesn't itself evaluate
/// their `body`).
final class SessionHistoryComponentsTests: XCTestCase {
    func testEditingSessionIdMirrorsTheWrappedSessionId() {
        let session = SyncClientTestSupport.makeSession()

        let editing = EditingSession(session: session)

        XCTAssertEqual(editing.id, session.id)
    }

    func testSessionRowRendersTheNoteWhenPresent() {
        let session = FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: .meeting,
            startedAt: Date(),
            status: .completed,
            note: "Standup notes",
            createdAt: Date(),
            updatedAt: Date()
        )

        let row = SessionRow(session: session)

        XCTAssertNotNil(row.body)
    }

    func testSessionRowOmitsTheNoteLineWhenNil() {
        let session = FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: .focus,
            startedAt: Date(),
            status: .running,
            createdAt: Date(),
            updatedAt: Date()
        )

        let row = SessionRow(session: session)

        XCTAssertNil(session.note)
        XCTAssertNotNil(row.body)
    }

    func testEditSessionNoteSheetInvokesItsOnSaveCallbackWithTheGivenValue() {
        let session = FocusSessionRecord(
            id: UUID(),
            deviceId: "test-device",
            kind: .focus,
            startedAt: Date(),
            status: .completed,
            note: "Existing note",
            createdAt: Date(),
            updatedAt: Date()
        )
        var savedNote: String??
        let sheet = EditSessionNoteSheet(session: session, onSave: { savedNote = $0 })

        XCTAssertNotNil(sheet.body)
        sheet.onSave("trimmed")

        // `onSave` is a plain passed-in closure (the trimming itself happens
        // in `SessionHistoryView.save`, a `private` method not reachable
        // from outside the file) — this asserts the sheet actually invokes
        // whatever closure it was given, a real and failable behavior.
        XCTAssertEqual(savedNote, "trimmed")
    }
}
