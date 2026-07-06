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
        let keychain = InMemoryKeychainStore()

        let first = DeviceIdProvider.currentDeviceId(defaults: defaults, keychain: keychain)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(keychain.read(key: "com.rizeclone.mobile.deviceId"), first)
    }

    func testCurrentDeviceIdReturnsTheSameValueOnSubsequentCalls() {
        let defaults = makeDefaults()
        let keychain = InMemoryKeychainStore()

        let first = DeviceIdProvider.currentDeviceId(defaults: defaults, keychain: keychain)
        let second = DeviceIdProvider.currentDeviceId(defaults: defaults, keychain: keychain)

        XCTAssertEqual(first, second)
    }

    func testCurrentDeviceIdSurvivesASimulatedRelaunchViaTheSameKeychain() {
        let defaults = makeDefaults()
        let keychain = InMemoryKeychainStore()
        let beforeRelaunch = DeviceIdProvider.currentDeviceId(defaults: defaults, keychain: keychain)

        // A fresh `UserDefaults` handle onto an empty suite, simulating a new
        // process — but the same Keychain, which is what actually persists
        // across a relaunch/reinstall in production.
        let freshDefaults = makeDefaults()
        let afterRelaunch = DeviceIdProvider.currentDeviceId(defaults: freshDefaults, keychain: keychain)

        XCTAssertEqual(beforeRelaunch, afterRelaunch)
    }

    func testCurrentDeviceIdIsIsolatedPerKeychain() {
        let defaults = makeDefaults()
        let firstKeychain = InMemoryKeychainStore()
        let secondKeychain = InMemoryKeychainStore()

        let firstId = DeviceIdProvider.currentDeviceId(defaults: defaults, keychain: firstKeychain)
        let secondId = DeviceIdProvider.currentDeviceId(defaults: makeDefaults(), keychain: secondKeychain)

        XCTAssertNotEqual(firstId, secondId)
    }

    // MARK: Keychain migration (RIZ-46)

    func testCurrentDeviceIdMigratesAnExistingUserDefaultsValueToKeychainOnce() {
        let defaults = makeDefaults()
        let keychain = InMemoryKeychainStore()
        defaults.set("legacy-device-id", forKey: "com.rizeclone.mobile.deviceId")

        let migrated = DeviceIdProvider.currentDeviceId(defaults: defaults, keychain: keychain)

        XCTAssertEqual(migrated, "legacy-device-id")
        XCTAssertEqual(keychain.read(key: "com.rizeclone.mobile.deviceId"), "legacy-device-id")
        XCTAssertNil(defaults.string(forKey: "com.rizeclone.mobile.deviceId"))
    }

    func testCurrentDeviceIdPrefersKeychainOverAStaleUserDefaultsValue() {
        let defaults = makeDefaults()
        let keychain = InMemoryKeychainStore()
        keychain.write("keychain-device-id", key: "com.rizeclone.mobile.deviceId")
        defaults.set("stale-legacy-id", forKey: "com.rizeclone.mobile.deviceId")

        let resolved = DeviceIdProvider.currentDeviceId(defaults: defaults, keychain: keychain)

        XCTAssertEqual(resolved, "keychain-device-id")
    }
}
