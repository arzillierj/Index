import Foundation
import Security

/// Persistent stand-in for Sign in with Apple while paid Developer
/// Program enrollment is pending. The UUID stored under
/// `Self.keychainAccount` plays the same role as Apple's
/// `userIdentifier` — stable across app launches and usable as the
/// `Profile.userId` cross-reference.
///
/// **Storage** (audit H21): Keychain (`SecItemAdd` with
/// `kSecAttrAccessibleAfterFirstUnlock` + `kSecAttrSynchronizable`)
/// instead of UserDefaults. UserDefaults clears on uninstall and is
/// world-readable from a backup; Keychain is encrypted at rest, and
/// when the user has iCloud Keychain enabled (default on most
/// installs) the synchronizable flag preserves the userId across
/// uninstall + reinstall — restoring the same Profile-key on next
/// launch instead of triggering the orphan-migration prompt.
///
/// First launch after the H21 upgrade copies any pre-existing
/// UserDefaults value into the Keychain and clears the UserDefaults
/// entry, so existing installs preserve identity across the storage
/// migration.
@Observable
final class DevIdentityService: IdentityService {
    /// Legacy UserDefaults key, read once at init for the one-shot
    /// migration into Keychain. Kept as `static let userDefaultsKey`
    /// so any debug tooling that referenced it still resolves.
    static let userDefaultsKey = "index.dev.userId"

    private static let keychainAccount = "index.dev.userId"
    private static let keychainService = Bundle.main.bundleIdentifier ?? "com.yanni.Index"

    private(set) var currentUserId: String?

    init() {
        if let existing = Self.readKeychain() {
            currentUserId = existing
            return
        }
        // One-shot UD → Keychain migration. If the legacy UD value
        // exists, copy to Keychain and clear UD so the next init
        // reads cleanly from Keychain. Preserves identity across the
        // H21 upgrade for users on existing installs (otherwise they
        // would land in the orphan-Profile migration prompt).
        if let legacy = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           Self.writeKeychain(value: legacy) {
            UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
            currentUserId = legacy
            return
        }
        currentUserId = nil
    }

    var isAuthenticated: Bool { currentUserId != nil }

    func signIn() async throws -> String {
        if let existing = currentUserId {
            return existing
        }
        let new = UUID().uuidString
        guard Self.writeKeychain(value: new) else {
            throw IdentityError.signInFailed("Keychain write failed.")
        }
        currentUserId = new
        return new
    }

    func signOut() async {
        Self.deleteKeychain()
        currentUserId = nil
    }

    // MARK: - Keychain helpers

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      keychainService,
            kSecAttrAccount as String:      keychainAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    @discardableResult
    private static func writeKeychain(value: String) -> Bool {
        let data = Data(value.utf8)
        // Delete any existing entry (same account + service +
        // synchronizable) before adding so SecItemAdd doesn't fail
        // with errSecDuplicateItem. Keychain has no native "upsert."
        deleteKeychain()
        let attrs: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        keychainService,
            kSecAttrAccount as String:        keychainAccount,
            kSecAttrAccessible as String:     kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: true,
            kSecValueData as String:          data,
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String:              kSecClassGenericPassword,
            kSecAttrService as String:        keychainService,
            kSecAttrAccount as String:        keychainAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
