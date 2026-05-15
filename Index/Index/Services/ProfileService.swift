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

    // MARK: - Phase 7 Settings update methods
    //
    // Each method mutates a single field on `activeProfile` and saves
    // explicitly. SettingsView surfaces save failures as a non-blocking
    // banner per the audit transactional-save discipline (H6 / H12).
    // Each throws on save failure so callers can decide whether to keep
    // the sheet open or dismiss.

    enum ProfileUpdateError: Error {
        case noActiveProfile
        case saveFailed(Error)
    }

    private func mutate(
        in context: ModelContext,
        _ change: (Profile) -> Void
    ) throws {
        guard let p = activeProfile else { throw ProfileUpdateError.noActiveProfile }
        change(p)
        do { try context.save() }
        catch { throw ProfileUpdateError.saveFailed(error) }
    }

    func updateName(_ name: String, in context: ModelContext) throws {
        try mutate(in: context) { $0.name = name.trimmingCharacters(in: .whitespaces) }
    }

    func updateAge(_ age: Int, in context: ModelContext) throws {
        try mutate(in: context) { $0.age = age }
    }

    func updateHeight(_ heightCm: Double, in context: ModelContext) throws {
        try mutate(in: context) { $0.heightCm = heightCm }
    }

    func updateSex(_ sex: Sex, in context: ModelContext) throws {
        try mutate(in: context) { $0.sex = sex }
    }

    func updateGoal(_ goal: Goal, in context: ModelContext) throws {
        try mutate(in: context) { $0.goal = goal }
    }

    func updateCalorieAdjustment(_ kcal: Double, in context: ModelContext) throws {
        try mutate(in: context) { $0.calorieAdjustmentKcal = kcal }
    }

    func setEatBackWorkoutCalories(_ enabled: Bool, in context: ModelContext) throws {
        try mutate(in: context) { $0.eatBackWorkoutCalories = enabled }
    }

    func setManualWeightLoggingEnabled(_ enabled: Bool, in context: ModelContext) throws {
        try mutate(in: context) { $0.manualWeightLoggingEnabled = enabled }
    }

    func setManualFitnessLoggingEnabled(_ enabled: Bool, in context: ModelContext) throws {
        try mutate(in: context) { $0.manualFitnessLoggingEnabled = enabled }
    }

    func updateProteinTarget(_ grams: Double, in context: ModelContext) throws {
        try mutate(in: context) { $0.proteinTargetG = grams }
    }

    func updateTargetWeight(_ kg: Double, hasTarget: Bool, in context: ModelContext) throws {
        try mutate(in: context) {
            $0.targetWeightKg = kg
            $0.hasTargetWeight = hasTarget
        }
    }

    func setModuleEnabled(_ module: Module, enabled: Bool, in context: ModelContext) throws {
        try mutate(in: context) {
            var modules = $0.enabledModules
            if enabled { modules.insert(module) } else { modules.remove(module) }
            $0.enabledModules = modules
        }
    }

    /// Phase 7c — wipes all per-user logged data (weights, workouts,
    /// strength sessions, nutrition entries, daily health metrics,
    /// food cache). PRESERVES `Profile` AND the `UserExercise`
    /// library (so the user keeps their exercise picks). HK
    /// previously-imported rows return on next observer fire if HK
    /// auth is still granted (UUID dedup keeps re-imports from
    /// duplicating).
    func resetAllData(in context: ModelContext) throws {
        do {
            try context.delete(model: WeightEntry.self)
            try context.delete(model: WorkoutSession.self)
            try context.delete(model: StrengthSession.self)
            // ExercisePerformance + SetEntry cascade-delete with
            // their parent StrengthSession (cascade rule on the
            // @Relationship), so we don't have to enumerate them.
            try context.delete(model: NutritionEntry.self)
            try context.delete(model: DailyHealthMetrics.self)
            try context.delete(model: FoodProduct.self)
            try context.save()
        } catch {
            throw ProfileUpdateError.saveFailed(error)
        }
    }

    /// Phase 7c — full account wipe. Removes everything including
    /// `Profile` and the `UserExercise` library, signs out of the
    /// identity provider, and clears `activeProfile`. ContentView
    /// observes the nil profile and routes back to OnboardingView
    /// for a fresh start.
    func deleteAccount(in context: ModelContext) async throws {
        do {
            try context.delete(model: WeightEntry.self)
            try context.delete(model: WorkoutSession.self)
            try context.delete(model: StrengthSession.self)
            try context.delete(model: NutritionEntry.self)
            try context.delete(model: DailyHealthMetrics.self)
            try context.delete(model: FoodProduct.self)
            try context.delete(model: UserExercise.self)
            try context.delete(model: Profile.self)
            try context.save()
        } catch {
            throw ProfileUpdateError.saveFailed(error)
        }
        await identity.signOut()
        activeProfile = nil
        orphanProfileForMigration = nil
    }

    /// Phase 7c — sign out without wiping data. Clears
    /// IdentityService state; the existing Profile remains on disk
    /// (becomes orphan-eligible on the next sign-in if a different
    /// userId comes back). ContentView observes the nil profile and
    /// routes to OnboardingView.
    func signOut() async {
        await identity.signOut()
        activeProfile = nil
        orphanProfileForMigration = nil
    }
}
