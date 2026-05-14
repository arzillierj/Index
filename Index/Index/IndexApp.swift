import SwiftUI
import SwiftData

@main
struct IndexApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema(IndexSchemaV2.models)
        // Local SwiftData store. The CloudKit container is intentionally NOT
        // configured yet — pending paid Developer Program enrollment. When
        // enabled, the ModelConfiguration gets
        //   cloudKitDatabase: .private("iCloud.com.yanni.Index")
        // and IndexSchemaV1 ships unchanged (all properties default, all
        // relationships optional, no @Attribute(.unique)).
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: IndexMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @State private var profileService = ProfileService(identity: AppDependencies.identity)
    @State private var hkService = HealthKitService()

    init() {
        // ONE-SHOT DATA WIPE — remove after running once on device.
        //
        // Recovery path for a corrupted WeightEntry (~5×10³⁸ kg) that
        // traps BodyView.formatKg → Int(kg) on launch before any UI can
        // be reached. Reinstalling the app from the home screen did
        // not clear the SwiftData store, so the wipe has to run from
        // inside the app itself before @Query observers fire.
        //
        // Runs in init() so it commits before WindowGroup → ContentView
        // body evaluates and triggers @Query. Profile, UserExercise,
        // FoodProduct, and PhotoEstimateLog rows are preserved.
        let wipeKey = "didOneShotWipe_2026_05_14"
        if !UserDefaults.standard.bool(forKey: wipeKey) {
            performOneShotWipe()
            UserDefaults.standard.set(true, forKey: wipeKey)
        }
    }

    private func performOneShotWipe() {
        let ctx = modelContainer.mainContext
        try? ctx.delete(model: WeightEntry.self)
        try? ctx.delete(model: WorkoutSession.self)
        try? ctx.delete(model: StrengthSession.self)
        try? ctx.delete(model: ExercisePerformance.self)
        try? ctx.delete(model: SetEntry.self)
        try? ctx.delete(model: NutritionEntry.self)
        try? ctx.delete(model: DailyHealthMetrics.self)
        do {
            try ctx.save()
        } catch {
            print("[OneShotWipe] save failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(profileService)
                .environment(hkService)
        }
        .modelContainer(modelContainer)
    }
}
