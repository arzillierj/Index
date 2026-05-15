import Foundation
import SwiftData

/// Source of truth for the active Profile. Every screen reads from
/// `activeProfile` (set after `refresh(in:)` is called against the root
/// view's `ModelContext`). The service does not hold a ModelContext — it
/// asks for one at each call so a single instance survives container
/// rebuilds (e.g. erase-all-data flows).
///
/// Migration path: when the identity provider's userId changes (most
/// importantly: Personal Team → paid team Sign in with Apple, which returns
/// a different `userIdentifier`), `refresh(in:)` looks for an orphan
/// Profile — exactly one Profile exists on the device but its `userId`
/// doesn't match. The caller surfaces a "Found previous data, import?"
/// prompt and then calls `acceptMigration(in:)` or `declineMigration(in:)`.
@Observable
@MainActor
final class ProfileService {
    private let identity: any IdentityService

    private(set) var activeProfile: Profile?
    private(set) var orphanProfileForMigration: Profile?

    init(identity: any IdentityService) {
        self.identity = identity
    }

    /// Loads the Profile matching the current `IdentityService.currentUserId`.
    /// If no exact match exists but a single orphan does, stage it for
    /// migration. Multiple-orphan case falls through to "no profile" — the
    /// onboarding flow then creates a fresh one.
    func refresh(in context: ModelContext) {
        guard let userId = identity.currentUserId else {
            activeProfile = nil
            orphanProfileForMigration = nil
            return
        }
        let descriptor = FetchDescriptor<Profile>()
        let profiles = (try? context.fetch(descriptor)) ?? []
        if let match = profiles.first(where: { $0.userId == userId }) {
            activeProfile = match
            orphanProfileForMigration = nil
            return
        }
        // FUTURE: handle the >1-orphan case if it ever shows up in practice —
        // a Settings affordance to pick which profile to keep. For now,
        // single-user typical case only.
        if profiles.count == 1, let orphan = profiles.first {
            activeProfile = nil
            orphanProfileForMigration = orphan
        } else {
            activeProfile = nil
            orphanProfileForMigration = nil
        }
    }

    /// Confirm migration: re-key the orphan Profile to the active userId.
    /// The Profile retains all of its data (weight entries, workouts,
    /// etc.) because those are independent rows — only `Profile.userId`
    /// changes.
    ///
    /// Audit H6 — explicit `try context.save()`. SwiftData autosave
    /// fires "next runloop tick when dirty"; an app kill between the
    /// userId mutation and the autosave would lose the re-key and the
    /// next launch would re-present the migration prompt.
    func acceptMigration(in context: ModelContext) {
        guard let orphan = orphanProfileForMigration,
              let userId = identity.currentUserId else { return }
        orphan.userId = userId
        do {
            try context.save()
        } catch {
            print("[ProfileService] acceptMigration save failed: \(error)")
        }
        activeProfile = orphan
        orphanProfileForMigration = nil
    }

    /// Decline migration: delete the orphan and create a fresh Profile
    /// keyed to the active userId. Caller is responsible for confirming
    /// destructive intent in the UI before invoking this.
    ///
    /// Audit H6 — both the delete and the subsequent insert are wrapped
    /// in a single explicit save so an app kill between operations
    /// can't leave the user with no Profile (which would silently
    /// route them back through OnboardingView and create yet another).
    func declineMigration(in context: ModelContext) {
        if let orphan = orphanProfileForMigration {
            context.delete(orphan)
        }
        orphanProfileForMigration = nil
        createFreshProfile(in: context)
        do {
            try context.save()
        } catch {
            print("[ProfileService] declineMigration save failed: \(error)")
        }
    }

    /// Onboarding-completion path: no Profile exists, create one keyed
    /// to the current userId. Caller fills in name/age/etc. after this
    /// returns. Save is the caller's responsibility (e.g.,
    /// ContentView.completeOnboarding wraps the inserts + save in one
    /// transaction — audit H12).
    func createFreshProfile(in context: ModelContext) {
        guard let userId = identity.currentUserId else { return }
        let profile = Profile(userId: userId)
        context.insert(profile)
        activeProfile = profile
    }
}
