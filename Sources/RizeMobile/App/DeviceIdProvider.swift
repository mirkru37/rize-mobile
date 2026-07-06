import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Resolves a stable, per-install device identifier for `GRDBLocalStore`/the
/// sync client (`APIClient`, `AuthService`) to tag rows and `device.id` with.
///
/// **Keychain migration (RIZ-46):** this identifier now lives in the
/// Keychain, not `UserDefaults`. Earlier versions of this app (RIZ-43-45)
/// persisted it in `UserDefaults`, since at the time there was no
/// Keychain-backed storage seam to reuse and the value wasn't yet sent to a
/// server that could use it to recognize a reconnecting device. Now that
/// `device.id` is echoed back by `register`/`login` for reconnect (see
/// [[api-reference]]), losing it on reinstall/restore would fragment a
/// user's history across a new `device_id` unnecessarily, so it belongs in
/// the Keychain like the rest of this app's durable credentials.
///
/// On first access after upgrading, if a device id is found in the legacy
/// `UserDefaults` location, it is moved to the Keychain once and the
/// `UserDefaults` copy is removed; every call thereafter reads/writes the
/// Keychain only.
enum DeviceIdProvider {
    private static let deviceIdKey = "com.rizeclone.mobile.deviceId"

    /// Returns the persisted device id, generating and persisting one on
    /// first call. Every subsequent call (including across app relaunches,
    /// reinstalls that restore Keychain data, and app updates) returns the
    /// same value.
    static func currentDeviceId(
        defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainStore()
    ) -> String {
        if let stored = keychain.read(key: deviceIdKey) {
            return stored
        }

        if let legacy = defaults.string(forKey: deviceIdKey) {
            keychain.write(legacy, key: deviceIdKey)
            defaults.removeObject(forKey: deviceIdKey)
            return legacy
        }

        let generated = generateDeviceId()
        keychain.write(generated, key: deviceIdKey)
        return generated
    }

    private static func generateDeviceId() -> String {
        #if canImport(UIKit)
            UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
            UUID().uuidString
        #endif
    }
}
