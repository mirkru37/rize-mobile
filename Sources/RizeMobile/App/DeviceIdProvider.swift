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
    ///
    /// `idGenerator` is a seam over first-call id generation (production
    /// defaults to `generateDeviceId()`, i.e. `UIDevice.identifierForVendor`
    /// where available). It exists so tests can control generation
    /// deterministically: `identifierForVendor` is stable per app
    /// installation on a given device/simulator, not per call, so two
    /// providers backed by two empty Keychains in the *same* test process
    /// would otherwise resolve to the same real `identifierForVendor` and
    /// only appear "isolated" by accident on hosts where `UIKit` isn't
    /// importable (see RIZ-65).
    static func currentDeviceId(
        defaults: UserDefaults = .standard,
        keychain: KeychainStoring = KeychainStore(),
        idGenerator: @escaping () -> String = generateDeviceId
    ) -> String {
        if let stored = keychain.read(key: deviceIdKey) {
            return stored
        }

        if let legacy = defaults.string(forKey: deviceIdKey) {
            keychain.write(legacy, key: deviceIdKey)
            defaults.removeObject(forKey: deviceIdKey)
            return legacy
        }

        let generated = idGenerator()
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
