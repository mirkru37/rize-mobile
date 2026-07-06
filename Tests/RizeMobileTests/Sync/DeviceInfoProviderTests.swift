import XCTest
@testable import RizeMobile

/// Covers `DeviceInfoProvider.current(deviceId:bundle:)` (RIZ-66) — the only
/// injectable seam is `bundle`, so tests focus on the `appVersion` mapping
/// (present/missing/non-string `CFBundleShortVersionString`) and on the
/// fields that don't depend on live `UIDevice` state.
final class DeviceInfoProviderTests: XCTestCase {
    /// Builds a throwaway `Bundle` backed by a real Info.plist on disk,
    /// matching `BackendConfigTests.makeBundle` — `Bundle` can't be reliably
    /// subclassed to override `infoDictionary` (its Objective-C
    /// implementation doesn't consistently dispatch through the Swift
    /// override), so a real on-disk bundle is the only way to control what
    /// it reports.
    private func makeBundle(infoDictionary: [String: Any]) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceInfoProviderTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundleURL) }

        let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: infoDictionary,
            format: .xml,
            options: 0
        )
        try plistData.write(to: infoPlistURL)

        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    func testCurrentEchoesDeviceIdAndPlatform() {
        let info = DeviceInfoProvider.current(deviceId: "device-123", bundle: .main)

        XCTAssertEqual(info.id, "device-123")
        XCTAssertEqual(info.platform, "ios")
    }

    func testCurrentReadsAppVersionFromBundleInfoDictionary() throws {
        let bundle = try makeBundle(infoDictionary: ["CFBundleShortVersionString": "2.5.1"])

        let info = DeviceInfoProvider.current(deviceId: "device-1", bundle: bundle)

        XCTAssertEqual(info.appVersion, "2.5.1")
    }

    func testCurrentDefaultsAppVersionWhenKeyIsMissing() throws {
        let bundle = try makeBundle(infoDictionary: [:])

        let info = DeviceInfoProvider.current(deviceId: "device-1", bundle: bundle)

        XCTAssertEqual(info.appVersion, "0.0.0")
    }

    func testCurrentDefaultsAppVersionWhenValueIsNotAString() throws {
        let bundle = try makeBundle(infoDictionary: ["CFBundleShortVersionString": 42])

        let info = DeviceInfoProvider.current(deviceId: "device-1", bundle: bundle)

        XCTAssertEqual(info.appVersion, "0.0.0")
    }

    func testCurrentDefaultsAppVersionWhenInfoDictionaryIsNil() throws {
        // A bundle directory with no Info.plist at all, so
        // `bundle.infoDictionary` itself is `nil` (rather than an empty
        // dictionary) — exercises the optional-chaining branch distinct
        // from `testCurrentDefaultsAppVersionWhenKeyIsMissing`.
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeviceInfoProviderTests-noplist-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundleURL) }
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))

        let info = DeviceInfoProvider.current(deviceId: "device-1", bundle: bundle)

        XCTAssertEqual(info.appVersion, "0.0.0")
    }
}
