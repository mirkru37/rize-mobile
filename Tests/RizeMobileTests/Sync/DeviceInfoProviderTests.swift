import XCTest
@testable import RizeMobile

/// Covers `DeviceInfoProvider.current(deviceId:bundle:)` (RIZ-66) — the only
/// injectable seam is `bundle`, so tests focus on the `appVersion` mapping
/// (present/missing/non-string `CFBundleShortVersionString`) and on the
/// fields that don't depend on live `UIDevice` state.
final class DeviceInfoProviderTests: XCTestCase {
    func testCurrentEchoesDeviceIdAndPlatform() {
        let info = DeviceInfoProvider.current(deviceId: "device-123", bundle: .main)

        XCTAssertEqual(info.id, "device-123")
        XCTAssertEqual(info.platform, "ios")
    }

    func testCurrentReadsAppVersionFromBundleInfoDictionary() throws {
        let bundle = try XCTUnwrap(FakeBundle(infoDictionary: ["CFBundleShortVersionString": "2.5.1"]))

        let info = DeviceInfoProvider.current(deviceId: "device-1", bundle: bundle)

        XCTAssertEqual(info.appVersion, "2.5.1")
    }

    func testCurrentDefaultsAppVersionWhenKeyIsMissing() throws {
        let bundle = try XCTUnwrap(FakeBundle(infoDictionary: [:]))

        let info = DeviceInfoProvider.current(deviceId: "device-1", bundle: bundle)

        XCTAssertEqual(info.appVersion, "0.0.0")
    }

    func testCurrentDefaultsAppVersionWhenValueIsNotAString() throws {
        let bundle = try XCTUnwrap(FakeBundle(infoDictionary: ["CFBundleShortVersionString": 42]))

        let info = DeviceInfoProvider.current(deviceId: "device-1", bundle: bundle)

        XCTAssertEqual(info.appVersion, "0.0.0")
    }

    func testCurrentDefaultsAppVersionWhenInfoDictionaryIsNil() throws {
        let bundle = try XCTUnwrap(FakeBundle(infoDictionary: nil))

        let info = DeviceInfoProvider.current(deviceId: "device-1", bundle: bundle)

        XCTAssertEqual(info.appVersion, "0.0.0")
    }
}

/// A `Bundle` subclass that overrides `infoDictionary` with a canned value.
/// Failable (mirroring `Bundle.init?(path:)`) so no force unwrap is needed to
/// bridge `Bundle`'s own failable designated initializer.
private final class FakeBundle: Bundle, @unchecked Sendable {
    private let fakeInfoDictionary: [String: Any]?

    init?(infoDictionary: [String: Any]?) {
        fakeInfoDictionary = infoDictionary
        super.init(path: Bundle.main.bundlePath)
    }

    override var infoDictionary: [String: Any]? {
        fakeInfoDictionary
    }
}
