import XCTest
@testable import RizeMobile

/// Covers `FocusSessionKind`/`FocusSessionStatus`'s UI display extensions
/// (RIZ-66) — exhaustive per case since these are plain switches with no
/// other branching.
final class FocusSessionKindDisplayTests: XCTestCase {
    func testFocusKindDisplayNames() {
        XCTAssertEqual(FocusSessionKind.focus.displayName, "Focus")
        XCTAssertEqual(FocusSessionKind.breakTime.displayName, "Break")
        XCTAssertEqual(FocusSessionKind.meeting.displayName, "Meeting")
    }

    func testFocusKindTierBadges() {
        XCTAssertEqual(FocusSessionKind.focus.tierBadge, "Focus")
        XCTAssertEqual(FocusSessionKind.breakTime.tierBadge, "Manual")
        XCTAssertEqual(FocusSessionKind.meeting.tierBadge, "Manual")
    }

    func testFocusStatusDisplayNames() {
        XCTAssertEqual(FocusSessionStatus.running.displayName, "Running")
        XCTAssertEqual(FocusSessionStatus.completed.displayName, "Completed")
        XCTAssertEqual(FocusSessionStatus.abandoned.displayName, "Abandoned")
    }
}
