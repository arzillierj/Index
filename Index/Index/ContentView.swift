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

    /// UserDefaults flag for the one-time
    /// `Profile.calorieAdjustmentKcal` sign migration. Set the first
    /// time `.task` runs (regardless of whether a profile existed to
    /// migrate) so the migration never re-fires on subsequent launches.
    static let calorieAdjustmentSignMigratedKey = "calorieAdjustmentSignMigrated"

    @State private var showStoreResetAlert = false
    @State private var showHardError = false
    @State private var selectedTab: TabSlot = .body

    private enum TabSlot: Hashable {
        case body, fitness, nutrition
    }

    /// Per-module accent for the TabView. Whichever tab is active drives
    /// the active-indicator color, the Log button tint inside that tab's
    /// NavigationStack, the brain insight sparkle, the chart highlights,
    /// and any other `.foregroundStyle(.tint)` site that lives in the
    /// module's main screen. Data-viz colors (HR red, Distance blue,
    /// SWOLF teal, Energy orange) come from IndexPalette.Data.* directly
    /// so they don't shift when the tab changes.
    private var currentTabAccent: Color {
        switch selectedTab {
        case .body:      return IndexPalette.Module.body
        case .fitness:   return IndexPalette.Module.fitness
        case .nutrition: return IndexPalette.Module.nutrition
        }
    }

    var body: some View {
        Group {
            if showHardError {
                hardErrorScreen
            } else if let orphan = profileService.orphanProfileForMigration {
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
            // First: was the ModelContainer init unrecoverable? If so,
            // we're running on the in-memory fallback store and any
            // writes are ephemeral. Show the hard-error screen and
            // skip everything else; there's no Profile to refresh and
            // no HK bootstrap that would survive.
            if UserDefaults.standard.bool(forKey: IndexApp.hardErrorFlagKey) {
                showHardError = true
                return
            }

            // Resolve current identity → active Profile (or orphan, or
            // neither). Then surface the migration-recovery alert if
            // the ModelContainer init had to wipe the store on this
            // launch. Only then arm HK observers, and only when there's
            // a Profile to anchor mirrored data to (audit H11 — HK
            // bootstrap during the orphan / onboarding paths could try
            // to mirror data into a profile-less store).
            profileService.refresh(in: modelContext)

            // One-time sign migration for Profile.calorieAdjustmentKcal.
            // Pre-fix, positive numbers stored "deficit magnitude"; post-
            // fix, negative = deficit / positive = surplus. Negate any
            // existing positive value so a legacy +500 becomes -500
            // under the new convention. Set the flag unconditionally
            // after the check so a fresh install (no profile yet) still
            // marks the migration done — its onboarding-time defaults
            // are already in the new convention.
            if !UserDefaults.standard.bool(forKey: Self.calorieAdjustmentSignMigratedKey) {
                if let profile = profileService.activeProfile,
                   profile.calorieAdjustmentKcal > 0 {
                    profile.calorieAdjustmentKcal = -profile.calorieAdjustmentKcal
                    do { try modelContext.save() }
                    catch { print("[ContentView] calorie-adjustment sign migration save failed: \(error)") }
                }
                UserDefaults.standard.set(true, forKey: Self.calorieAdjustmentSignMigratedKey)
            }

            if UserDefaults.standard.bool(forKey: IndexApp.storeResetFlagKey) {
                showStoreResetAlert = true
                UserDefaults.standard.set(false, forKey: IndexApp.storeResetFlagKey)
            }

            // HK side-channel removed (audit H10) — HealthKitService
            // now holds the ModelContainer it was constructed with.

            // Demo-mode seeding. The active store is already the
            // demo store at this point (ModelContainer was built
            // against `Index-demo.store` in IndexApp because the
            // flag was on at launch). Seed only when the demo
            // store has no Profile yet — every subsequent launch
            // reuses the already-generated dataset. After seed,
            // ProfileService.refresh re-reads so ContentView
            // routes directly into the tabs instead of
            // OnboardingView.
            if DemoMode.isEnabled, !DemoDataService.isSeeded(in: modelContext) {
                do {
                    try DemoDataService.seedFreshDataset(in: modelContext)
                    profileService.refresh(in: modelContext)
                } catch {
                    print("[ContentView] demo seed failed: \(error)")
                }
            }

            // HK bootstrap is skipped in demo mode — the demo
            // store is intentionally offline, and pulling real
            // weights/workouts in would mix real data with the
            // synthetic year.
            if profileService.activeProfile != nil, !DemoMode.isEnabled {
                await hkService.bootstrapIfAuthorized()
            }
        }
        .alert("Local data was reset", isPresented: $showStoreResetAlert) {
            Button("OK") {}
        } message: {
            Text("Your local data couldn't be migrated and was reset. Your Apple Health data is unaffected and will re-sync.")
        }
        // Notification-tap routing. NotificationService posts this
        // broadcast only when the app was NOT active at tap time
        // (cold launch from notification, or background resume), so
        // there's no risk of yanking the user mid-task. Tab swap
        // honors the destinationTab payload.
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.tabRouteNotificationName)) { note in
            guard let tab = note.userInfo?[NotificationService.tabRouteUserInfoKey] as? String else { return }
            switch tab {
            case "body":     selectedTab = .body
            case "fitness":  selectedTab = .fitness
            case "nutrition": selectedTab = .nutrition
            default: break
            }
        }
    }

    // MARK: - Hard error screen
    //
    // Reached only when the ModelContainer init couldn't recover (both
    // the initial open AND the wipe-then-retry attempt failed) — see
    // IndexApp's recovery path. The app runs on an in-memory fallback
    // store, so anything the user logs is lost on next launch. Surface
    // this clearly + offer a "Reset all data" path that wipes the
    // store files manually.
    private var hardErrorScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(IndexPalette.Semantic.warning)
            Text("Index can't open your local data.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Your Apple Health data is unaffected. To recover, reset Index's local store and start fresh — or delete and reinstall the app from the home screen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
            Button("Reset all data and restart") {
                resetAndRestart()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 32)
        }
    }

    /// Hard-error recovery: wipe the SwiftData store files manually
    /// (mirrors IndexApp.deleteStoreFiles) then exit so the next launch
    /// performs a clean ModelContainer init. We don't reach into
    /// IndexApp here to avoid coupling — duplicate the file names
    /// instead. Worst case the wipe no-ops because the files weren't
    /// there; the next launch then has no store-conflict to resolve.
    private func resetAndRestart() {
        let fm = FileManager.default
        if let supportURL = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            for suffix in ["", "-shm", "-wal"] {
                let url = supportURL.appendingPathComponent("default.store\(suffix)")
                try? fm.removeItem(at: url)
            }
        }
        UserDefaults.standard.set(false, forKey: IndexApp.hardErrorFlagKey)
        UserDefaults.standard.set(true, forKey: IndexApp.storeResetFlagKey)
        // Trap to force the user back to the home screen — when they
        // tap Index again, the next ModelContainer init runs against a
        // clean directory.
        exit(0)
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
        TabView(selection: $selectedTab) {
            if profile.enabledModules.contains(.body) {
                Tab("Body", systemImage: "scalemass", value: TabSlot.body) {
                    IndexTabScaffold { BodyView() }
                }
            }
            if profile.enabledModules.contains(.fitness) {
                Tab("Fitness", systemImage: "figure.run", value: TabSlot.fitness) {
                    IndexTabScaffold { FitnessMainView() }
                }
            }
            if profile.enabledModules.contains(.nutrition) {
                Tab("Nutrition", systemImage: "fork.knife", value: TabSlot.nutrition) {
                    IndexTabScaffold { NutritionMainView() }
                }
            }
        }
        .tint(currentTabAccent)
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

        // Audit H12 — transactional save. SwiftData autosave is
        // "next runloop tick when dirty"; an app kill between this
        // call and the autosave would lose the entire onboarding
        // result. Explicit save closes that window. On failure we
        // log + continue so the user isn't trapped in a save loop;
        // they'd see the OnboardingView again on next launch and
        // the inserts would re-run.
        do {
            try modelContext.save()
        } catch {
            print("[ContentView] onboarding save failed: \(error)")
        }

        profileService.refresh(in: modelContext)
    }
}

// MARK: - Shared tab scaffold

/// Wraps each tab's root view in a `NavigationStack` plus the shared
/// warm-alabaster screen background.
///
/// Why a single wrapper: the status-bar region color used to read as
/// a "warmer strip" against the screen below because the navigation
/// bar's `toolbarBackground` was the alabaster surface (#FAF8F5) but
/// the ScrollView body fell through to the iOS system default
/// background (a slightly cooler shade in iOS 26). Painting the
/// scaffold the SAME alabaster as the toolbar removes the seam — the
/// background is continuous from the top edge through the status-bar
/// region into the page content. `.ignoresSafeArea()` extends the
/// fill behind the toolbar so the seam can't reappear if a child's
/// toolbarBackground modifier ever gets dropped.
///
/// Tab-specific tinting (Body blue / Fitness coral / Nutrition teal)
/// lives on the TabView via `.tint(currentTabAccent)` and on the
/// per-module hero text — the scaffold background is intentionally
/// neutral so the accent isn't fighting the surface.
private struct IndexTabScaffold<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .background(
                    IndexPalette.Surface.background
                        .ignoresSafeArea()
                )
        }
    }
}
