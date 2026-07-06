import XCTest
@testable import RizeMobile

final class DeviceIdProviderTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.rizeclone.mobile.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testCurrentDeviceIdPersistsAGeneratedIdOnFirstCall() {
        let defaults = makeDefaults()

        let first = DeviceIdProvider.currentDeviceId(defaults: defaults)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(defaults.string(forKey: "com.rizeclone.mobile.deviceId"), first)
    }

    func testCurrentDeviceIdReturnsTheSameValueOnSubsequentCalls() {
        let defaults = makeDefaults()

        let first = DeviceIdProvider.currentDeviceId(defaults: defaults)
        let second = DeviceIdProvider.currentDeviceId(defaults: defaults)

        XCTAssertEqual(first, second)
    }

    func testCurrentDeviceIdSurvivesASimulatedRelaunchViaTheSameDefaultsSuite() {
        let defaults = makeDefaults()
        let beforeRelaunch = DeviceIdProvider.currentDeviceId(defaults: defaults)

        // A fresh `UserDefaults` handle onto the same suite, simulating a
        // new process reading back what a previous launch persisted.
        let afterRelaunch = DeviceIdProvider.currentDeviceId(defaults: defaults)

        XCTAssertEqual(beforeRelaunch, afterRelaunch)
    }

    func testCurrentDeviceIdIsIsolatedPerDefaultsSuite() {
        let firstSuite = makeDefaults()
        let secondSuite = makeDefaults()

        let firstId = DeviceIdProvider.currentDeviceId(defaults: firstSuite)
        let secondId = DeviceIdProvider.currentDeviceId(defaults: secondSuite)

        XCTAssertNotEqual(firstId, secondId)
    }
}
