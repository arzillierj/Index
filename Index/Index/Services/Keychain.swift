import Foundation
import Security

/// Thin wrapper over `SecItem*` for string-valued keychain
/// entries. Matches the pattern used inline in
/// `DevIdentityService` (audit H21): `kSecClassGenericPassword`,
/// `kSecAttrAccessibleAfterFirstUnlock`, `kSecAttrSynchronizable`
/// so iCloud Keychain syncs the value across the user's devices.
///
/// `service` is the bundle identifier — same value for every
/// item — so they coexist in a single Keychain access group.
/// `account` differentiates items (`index.dev.userId`,
/// `index.ai.anthropicAPIKey`, ...).
///
/// Existing inline implementations (DevIdentityService) keep
/// working unchanged; new services route through this helper to
/// avoid duplicating the SecItem boilerplate.
enum Keychain {

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.yanni.Index"
    }

    /// Reads the string value stored for `account`. Returns nil
    /// when nothing is stored OR the underlying SecItemCopyMatching
    /// failed for any reason — callers treat "missing" and
    /// "unreadable" identically (re-set on next user action).
    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String:         true,
            kSecMatchLimit as String:         kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    /// Writes a string value to `account`. Existing item under the
    /// same account is deleted first because `SecItemAdd` fails
    /// with `errSecDuplicateItem` if a row already exists — there
    /// is no native upsert.
    @discardableResult
    static func write(_ account: String, value: String) -> Bool {
        let data = Data(value.utf8)
        delete(account)
        let attrs: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrAccessible as String:     kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true,
            kSecValueData as String:          data,
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    /// Removes the entry under `account`. No-op if absent.
    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        service,
            kSecAttrAccount as String:        account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// True when a value is stored for `account`. Avoids returning
    /// the value itself — useful for UI gates that only need to
    /// know "is this configured" without re-reading sensitive data.
    static func has(_ account: String) -> Bool {
        read(account) != nil
    }
}
