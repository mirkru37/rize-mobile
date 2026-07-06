import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Builds the `device` object sent to `register`/`login`/`refresh`, per
/// [[api-reference]] §Auth. `id` is the persisted, Keychain-backed device id
/// from `DeviceIdProvider`, sent on every call so the server recognizes a
/// reconnecting device rather than registering a new one.
enum DeviceInfoProvider {
    static func current(deviceId: String, bundle: Bundle = .main) -> DeviceInfo {
        DeviceInfo(
            id: deviceId,
            platform: "ios",
            name: deviceName,
            model: deviceModel,
            osVersion: osVersion,
            appVersion: appVersion(bundle: bundle)
        )
    }

    private static var deviceName: String {
        #if canImport(UIKit)
            UIDevice.current.name
        #else
            "Unknown"
        #endif
    }

    private static var deviceModel: String {
        #if canImport(UIKit)
            UIDevice.current.model
        #else
            "Unknown"
        #endif
    }

    private static var osVersion: String {
        #if canImport(UIKit)
            UIDevice.current.systemVersion
        #else
            ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private static func appVersion(bundle: Bundle) -> String {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }
}
