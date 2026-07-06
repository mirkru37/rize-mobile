import Foundation
import Security

/// The Keychain seam used for every credential this app persists: the
/// refresh token and (per RIZ-46) the migrated device id. Never used for
/// anything else — access tokens are memory-only per [[security]].
///
/// Kept as a narrow key/value protocol (rather than exposing `SecItem*`
/// directly) so the sync/auth layer never touches `Security` directly and
/// tests can substitute an in-memory fake.
public protocol KeychainStoring: Sendable {
    func read(key: String) -> String?
    func write(_ value: String, key: String)
    func delete(key: String)
}

/// `Security`-framework-backed `KeychainStoring`, storing each value as a
/// generic password item keyed by `service` (fixed per app) + `account`
/// (the caller-supplied `key`).
///
/// Per [[security]] §Client-side token storage, this is the only storage this
/// app uses for the refresh token and the device id — never `UserDefaults` or
/// a plist.
public struct KeychainStore: KeychainStoring {
    private let service: String

    public init(service: String = "com.rizeclone.mobile") {
        self.service = service
    }

    public func read(key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }

        if read(key: key) != nil {
            let query = baseQuery(key: key)
            let update = [kSecValueData as String: data]
            SecItemUpdate(query as CFDictionary, update as CFDictionary)
            return
        }

        var addQuery = baseQuery(key: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    public func delete(key: String) {
        let query = baseQuery(key: key)
        SecItemDelete(query as CFDictionary)
    }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// An in-memory `KeychainStoring`, so tests never touch the real Keychain
/// (unavailable/unreliable in a plain `xctest` process without an app
/// host/entitlements) and so `AppEnvironment.inMemory()` (SwiftUI previews
/// and full-environment tests) never persists or shares credentials across
/// runs. Not used anywhere in the production (`AppEnvironment.live()`) path.
public final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    public init() {}

    public func read(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func write(_ value: String, key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }

    public func delete(key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
