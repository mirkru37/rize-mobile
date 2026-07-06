import Foundation

/// The backend's base URL (e.g. `https://api.rize-clone.example`), consumed
/// by `APIClient` to build every request path from [[api-reference]]'s
/// route table.
public struct BackendConfig: Equatable, Sendable {
    public var baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
    }
}

/// Resolves `BackendConfig` from whichever of this app's configuration seams
/// is populated, in priority order:
///
/// 1. A `UserDefaults` override (`backendBaseURLDefaultsKey`) — lets QA/internal
///    builds point at a staging backend without a rebuild.
/// 2. An Info.plist key (`RIZE_BACKEND_BASE_URL`), which `project.yml`/an
///    xcconfig can set per build configuration (Debug/Release/staging).
/// 3. `http://localhost:8080`, a sane default for local backend development.
public enum BackendConfigProvider {
    public static let backendBaseURLDefaultsKey = "com.rizeclone.mobile.backendBaseURL"
    private static let infoPlistKey = "RIZE_BACKEND_BASE_URL"
    private static let developmentFallbackString = "http://localhost:8080"

    public static func resolve(defaults: UserDefaults = .standard, bundle: Bundle = .main) -> BackendConfig {
        if let overridden = defaults.string(forKey: backendBaseURLDefaultsKey),
           let url = URL(string: overridden),
           url.host != nil
        {
            return BackendConfig(baseURL: url)
        }

        if let configured = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String,
           let url = URL(string: configured),
           url.host != nil
        {
            return BackendConfig(baseURL: url)
        }

        return BackendConfig(baseURL: developmentFallback)
    }

    static var developmentFallback: URL {
        guard let url = URL(string: developmentFallbackString) else {
            preconditionFailure("BackendConfigProvider's fallback URL literal is invalid")
        }
        return url
    }
}
