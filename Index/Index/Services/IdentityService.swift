import Foundation

/// Identity abstraction. Two implementations:
///   - `DevIdentityService` — UUID in UserDefaults. Used until paid Developer
///     Program enrollment completes, since real Sign in with Apple needs JWT
///     signing infrastructure that the Personal Team can't provide.
///   - `AppleSignInIdentityService` — real ASAuthorization flow. Stubbed
///     until enrollment lands.
///
/// The rest of the app calls `AppDependencies.identity.signIn()` — it never
/// branches on which concrete service is active. Swapping post-enrollment is
/// one line in `AppDependencies`.
protocol IdentityService: AnyObject {
    var currentUserId: String? { get }
    var isAuthenticated: Bool { get }
    func signIn() async throws -> String
    func signOut() async
}

enum IdentityError: Error {
    case signInCancelled
    case signInFailed(String)
}

/// Single seam between the app and whichever identity provider is active.
/// Swap the right-hand side to `AppleSignInIdentityService()` after paid
/// Developer Program enrollment completes — no other call sites change.
enum AppDependencies {
    static let identity: any IdentityService = DevIdentityService()
}
