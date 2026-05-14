import Foundation
import AuthenticationServices

/// Real Sign in with Apple, stubbed until paid Developer Program enrollment
/// is in place. The class exists so file structure and call sites can mature
/// against the eventual seam — the only change post-enrollment is filling in
/// these bodies and flipping `AppDependencies.identity` to point here.
///
/// FUTURE: The Personal Team returns a development-tier `userIdentifier`
/// that differs from the production one. After the team switch,
/// `ProfileService` should offer to migrate any orphan Profile (i.e. a
/// Profile whose `userId` doesn't match the newly-returned identifier but
/// is the only Profile on the device) rather than creating a fresh empty
/// Profile.
@Observable
final class AppleSignInIdentityService: IdentityService {
    var currentUserId: String? {
        fatalError("Pending paid Developer Program enrollment — use DevIdentityService.")
    }

    var isAuthenticated: Bool {
        fatalError("Pending paid Developer Program enrollment — use DevIdentityService.")
    }

    func signIn() async throws -> String {
        // FUTURE: Build ASAuthorizationAppleIDRequest with .fullName + .email scopes.
        // FUTURE: Run via ASAuthorizationController, bridge delegate callbacks
        //         to async/await with withCheckedThrowingContinuation.
        // FUTURE: Read .user (the stable userIdentifier) from the resulting
        //         ASAuthorizationAppleIDCredential, persist in Keychain
        //         (NOT UserDefaults — Keychain survives reinstall).
        // FUTURE: On subsequent launches, call provider.getCredentialState
        //         to detect revocation and clear local state if needed.
        fatalError("Pending paid Developer Program enrollment.")
    }

    func signOut() async {
        // FUTURE: Clear stored identifier from Keychain. Apple Sign-in itself
        //         is revoked from iOS Settings > Apple ID, not via API.
        fatalError("Pending paid Developer Program enrollment.")
    }
}
