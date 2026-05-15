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
    // Audit H7 — every member here is reachable from the rest of the
    // app (ProfileService, OnboardingView). When this stub eventually
    // becomes the live implementation, pre-flipping
    // `AppDependencies.identity` to point here BEFORE the bodies are
    // filled in must not trap the app. The previous fatalErrors were
    // the kind of refactor landmine that survives a partial wiring
    // commit and only manifests once a real user opens the app.
    //
    // Stubs return non-fatal default values:
    //   - `currentUserId` → nil (caller treats as "not signed in")
    //   - `isAuthenticated` → false
    //   - `signIn()` → throws IdentityError.signInFailed(...)
    //   - `signOut()` → no-op
    //
    // Each FUTURE comment from the original is preserved alongside.

    var currentUserId: String? {
        // FUTURE: Read the stable Apple userIdentifier from Keychain
        //         (where signIn persisted it after first auth).
        nil
    }

    var isAuthenticated: Bool {
        // FUTURE: provider.getCredentialState(forUserID:) check — also
        //         used to detect revocation between sessions.
        false
    }

    func signIn() async throws -> String {
        // FUTURE: Build ASAuthorizationAppleIDRequest with .fullName + .email scopes.
        // FUTURE: Run via ASAuthorizationController, bridge delegate callbacks
        //         to async/await with withCheckedThrowingContinuation.
        // FUTURE: Read .user (the stable userIdentifier) from the resulting
        //         ASAuthorizationAppleIDCredential, persist in Keychain
        //         (NOT UserDefaults — Keychain survives reinstall when
        //         iCloud Keychain sync is enabled; see DevIdentityService H21).
        // FUTURE: On subsequent launches, call provider.getCredentialState
        //         to detect revocation and clear local state if needed.
        throw IdentityError.signInFailed("Sign in with Apple isn't wired yet — pending paid Developer Program enrollment.")
    }

    func signOut() async {
        // FUTURE: Clear stored identifier from Keychain. Apple Sign-in itself
        //         is revoked from iOS Settings > Apple ID, not via API.
    }
}
