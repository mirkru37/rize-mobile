import XCTest
@testable import RizeMobile

final class DashboardViewTests: XCTestCase {
    func testPlaceholderDashboardViewInitializes() {
        let view = DashboardView()
        XCTAssertNotNil(view.body)
    }
}
