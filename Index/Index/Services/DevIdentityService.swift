import Foundation

/// Persistent stand-in for Sign in with Apple while paid Developer Program
/// enrollment is pending. The UUID stored under `userDefaultsKey` plays the
/// same role as Apple's `userIdentifier` — stable across app launches and
/// usable as the `Profile.userId` cross-reference.
@Observable
final class DevIdentityService: IdentityService {
    static let userDefaultsKey = "index.dev.userId"

    private(set) var currentUserId: String?

    init() {
        currentUserId = UserDefaults.standard.string(forKey: Self.userDefaultsKey)
    }

    var isAuthenticated: Bool { currentUserId != nil }

    func signIn() async throws -> String {
        if let existing = currentUserId {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: Self.userDefaultsKey)
        currentUserId = new
        return new
    }

    func signOut() async {
        UserDefaults.standard.removeObject(forKey: Self.userDefaultsKey)
        currentUserId = nil
    }
}
