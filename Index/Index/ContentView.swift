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
            // imports persist into our store.
            profileService.refresh(in: modelContext)
            if hkService.modelContext == nil {
                hkService.modelContext = modelContext
            }
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

    // MARK: - Body tab placeholder
    //
    // Phase 4 replaces this with the real BodyView. Lets us verify the
    // routing end-to-end in the simulator.
    private func bodyTabPlaceholder(profile: Profile) -> some View {
        VStack(spacing: 8) {
            Text("Index — Body").font(.title.italic())
            Text(profile.name.isEmpty ? "—" : profile.name)
                .foregroundStyle(.secondary)
            Text("userId: \(profile.userId)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding()
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
