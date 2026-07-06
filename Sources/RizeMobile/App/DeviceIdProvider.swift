import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Resolves a stable, per-install device identifier for `GRDBLocalStore`/the
/// future sync client to tag rows with.
///
/// The identifier is persisted in `UserDefaults` so it survives across app
/// launches: without persistence, `UIDevice.identifierForVendor` is stable
/// across launches on real devices but the fallback `UUID()` generated when
/// it's unavailable was previously regenerated on every launch, silently
/// fragmenting a single install's data across many `device_id`s.
///
/// This value is a device identifier, not a credential — unlike the access/
/// refresh tokens in [[security]], which must live in the Keychain — so
/// `UserDefaults` is an acceptable interim store. That said, `UserDefaults`
/// does not survive a reinstall the way Keychain (with the right
/// accessibility class) can; migrating this identifier to the Keychain is
/// planned alongside RIZ-46 (auth), once the client has a Keychain-backed
/// storage seam to reuse.
enum DeviceIdProvider {
    private static let deviceIdKey = "com.rizeclone.mobile.deviceId"

    /// Returns the persisted device id, generating and persisting one on
    /// first call. Every subsequent call (including across app relaunches,
    /// as long as `defaults` is backed by the same suite) returns the same
    /// value.
    static func currentDeviceId(defaults: UserDefaults = .standard) -> String {
        if let stored = defaults.string(forKey: deviceIdKey) {
            return stored
        }
        let generated = generateDeviceId()
        defaults.set(generated, forKey: deviceIdKey)
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
