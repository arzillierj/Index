import SwiftUI
import SwiftData

/// App root. Three paths:
///   1. Orphan Profile staged for migration → prompt to import or wipe.
///   2. Active Profile with onboardingCompleted == true → Body tab.
///   3. Otherwise → OnboardingView.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ProfileService.self) private var profileService
    @Environment(HealthKitService.self) private var hkService

    @State private var showStoreResetAlert = false

    var body: some View {
        Group {
            if let orphan = profileService.orphanProfileForMigration {
                migrationPrompt(orphan: orphan)
            } else if let profile = profileService.activeProfile,
                      profile.onboardingCompleted {
                bodyTabPlaceholder(profile: profile)
            } else {
                OnboardingView(identity: AppDependencies.identity) { draft in
                    completeOnboarding(draft: draft)
                }
            }
        }
        .task {
            // Resolve current identity → active Profile (or orphan, or
            // neither). Also wire HKService to the same context so its
            // imports persist into our store, and arm HK auto-import +
            // observers if the user has previously granted authorization.
            profileService.refresh(in: modelContext)
            if hkService.modelContext == nil {
                hkService.modelContext = modelContext
            }

            // Surface the migration-failure recovery alert once, if the
            // ModelContainer init had to wipe the store on this launch.
            if UserDefaults.standard.bool(forKey: IndexApp.storeResetFlagKey) {
                showStoreResetAlert = true
                UserDefaults.standard.set(false, forKey: IndexApp.storeResetFlagKey)
            }

            await hkService.bootstrapIfAuthorized()
        }
        .alert("Local data was reset", isPresented: $showStoreResetAlert) {
            Button("OK") {}
        } message: {
            Text("Your local data couldn't be migrated and was reset. Your Apple Health data is unaffected and will re-sync.")
        }
    }

    // MARK: - Migration prompt
    //
    // Surfaces when ProfileService.refresh found exactly one Profile on
    // device that doesn't match the current userId. The most likely cause:
    // the Personal Team SIWA userIdentifier changed to the paid-team one,
    // and we should re-key the existing Profile rather than abandon it.
    private func migrationPrompt(orphan: Profile) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Found previous data.")
                .font(.title.weight(.semibold))
            Text("A profile for \(orphan.name.isEmpty ? "someone on this device" : orphan.name) already exists. Import it under your new sign-in?")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button("Import previous data") {
                    profileService.acceptMigration(in: modelContext)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("Start fresh") {
                    profileService.declineMigration(in: modelContext)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    // MARK: - Main app tabs
    //
    // TabView containing every module the active Profile has enabled.
    // Body, Fitness, and Nutrition can each be toggled off in Settings.
    private func bodyTabPlaceholder(profile: Profile) -> some View {
        TabView {
            if profile.enabledModules.contains(.body) {
                Tab("Body", systemImage: "scalemass") {
                    NavigationStack { BodyView() }
                }
            }
            if profile.enabledModules.contains(.fitness) {
                Tab("Fitness", systemImage: "figure.run") {
                    NavigationStack { FitnessMainView() }
                }
            }
            if profile.enabledModules.contains(.nutrition) {
                Tab("Nutrition", systemImage: "fork.knife") {
                    NavigationStack { NutritionMainView() }
                }
            }
        }
    }

    // MARK: - Onboarding completion

    private func completeOnboarding(draft: OnboardingDraft) {
        // Create the Profile in one go — the sign-in step persisted the
        // UUID into IdentityService; the remaining steps lived in the
        // local draft. Writing here keeps onboarding-in-progress users
        // free of a half-built Profile row on disk.
        let profile = Profile(
            userId: draft.userId,
            name: draft.name,
            age: draft.age,
            heightCm: draft.heightCm,
            sex: draft.sex,
            activityLevel: draft.activityLevel,
            goal: draft.goal,
            targetWeightKg: draft.targetWeightKg,
            hasTargetWeight: draft.hasTargetWeight,
            units: .metric,
            enabledModules: draft.enabledModules,
            appleHealthAuthorized: draft.appleHealthAuthorized,
            onboardingCompleted: true
        )
        modelContext.insert(profile)

        // Sorted iteration so re-running onboarding produces deterministic
        // displayOrder per starter id.
        for (i, id) in draft.selectedExerciseIds.sorted().enumerated() {
            if let def = ExerciseCatalog.byId(id) {
                modelContext.insert(UserExercise.fromCatalog(def, displayOrder: i))
            }
        }

        profileService.refresh(in: modelContext)
    }
}
