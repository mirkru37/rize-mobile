import XCTest
@testable import RizeMobile

/// Covers `BackendConfigProvider.resolve(defaults:bundle:)`'s three-tier
/// priority (UserDefaults override → Info.plist key → hardcoded fallback)
/// and the hostless-URL guard added for RIZ-56 (see `Config.example.xcconfig`
/// for the xcconfig comment-parsing bug this guards against).
final class BackendConfigTests: XCTestCase {
    /// Builds a throwaway `Bundle` backed by a real Info.plist on disk, so
    /// `BackendConfigProvider.resolve(bundle:)` exercises the same
    /// `object(forInfoDictionaryKey:)` code path it uses in production
    /// (Bundle can't be subclassed with a bare `init()` — it has no
    /// designated initializer for that).
    private func makeBundle(backendBaseURLValue: String?) throws -> Bundle {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackendConfigTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: bundleURL) }

        var infoDictionary: [String: Any] = [:]
        if let backendBaseURLValue {
            infoDictionary["RIZE_BACKEND_BASE_URL"] = backendBaseURLValue
        }
        let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: infoDictionary,
            format: .xml,
            options: 0
        )
        try plistData.write(to: infoPlistURL)

        return try XCTUnwrap(Bundle(url: bundleURL))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.rizeclone.mobile.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    func testResolveUsesThePlistValueWhenNoDefaultsOverrideIsSet() throws {
        let defaults = makeDefaults()
        let bundle = try makeBundle(backendBaseURLValue: "http://example.test:1234")

        let config = BackendConfigProvider.resolve(defaults: defaults, bundle: bundle)

        XCTAssertEqual(config.baseURL, try XCTUnwrap(URL(string: "http://example.test:1234")))
    }

    func testResolveFallsBackToTheLocalhostDefaultWhenPlistValueIsAbsentAndNoOverride() throws {
        let defaults = makeDefaults()
        let bundle = try makeBundle(backendBaseURLValue: nil)

        let config = BackendConfigProvider.resolve(defaults: defaults, bundle: bundle)

        XCTAssertEqual(config.baseURL, try XCTUnwrap(URL(string: "http://localhost:8080")))
    }

    func testResolveFallsBackToTheLocalhostDefaultWhenPlistValueIsEmptyAndNoOverride() throws {
        let defaults = makeDefaults()
        let bundle = try makeBundle(backendBaseURLValue: "")

        let config = BackendConfigProvider.resolve(defaults: defaults, bundle: bundle)

        XCTAssertEqual(config.baseURL, try XCTUnwrap(URL(string: "http://localhost:8080")))
    }

    func testResolvePrefersTheUserDefaultsOverrideOverThePlistValue() throws {
        let defaults = makeDefaults()
        defaults.set("http://override.test:9999", forKey: BackendConfigProvider.backendBaseURLDefaultsKey)
        let bundle = try makeBundle(backendBaseURLValue: "http://example.test:1234")

        let config = BackendConfigProvider.resolve(defaults: defaults, bundle: bundle)

        XCTAssertEqual(config.baseURL, try XCTUnwrap(URL(string: "http://override.test:9999")))
    }

    // MARK: H1 guard — hostless URLs must not be accepted (RIZ-56)

    func testResolveRejectsAHostlessPlistValueAndFallsBackToTheLocalhostDefault() throws {
        // "http:" is exactly what xcconfig's `//`-anywhere-is-a-comment rule
        // produces from an unescaped `http://localhost:8080` value — it must
        // never be accepted as a real base URL.
        let defaults = makeDefaults()
        let bundle = try makeBundle(backendBaseURLValue: "http:")

        let config = BackendConfigProvider.resolve(defaults: defaults, bundle: bundle)

        XCTAssertEqual(config.baseURL, try XCTUnwrap(URL(string: "http://localhost:8080")))
    }

    func testResolveRejectsAHostlessUserDefaultsOverrideAndFallsThroughToThePlistValue() throws {
        let defaults = makeDefaults()
        defaults.set("http:", forKey: BackendConfigProvider.backendBaseURLDefaultsKey)
        let bundle = try makeBundle(backendBaseURLValue: "http://example.test:1234")

        let config = BackendConfigProvider.resolve(defaults: defaults, bundle: bundle)

        XCTAssertEqual(config.baseURL, try XCTUnwrap(URL(string: "http://example.test:1234")))
    }
}
