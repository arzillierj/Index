import SwiftData

/// All 11 @Model types at v1.0.0. Every future schema change is a new
/// VersionedSchema appended below + a lightweight stage in IndexMigrationPlan.
enum IndexSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Profile.self,
            WeightEntry.self,
            DailyHealthMetrics.self,
            WorkoutSession.self,
            StrengthSession.self,
            ExercisePerformance.self,
            SetEntry.self,
            UserExercise.self,
            NutritionEntry.self,
            FoodProduct.self,
            PhotoEstimateLog.self,
        ]
    }
}

/// Wired into the ModelContainer from day one. Empty stages list now; every
/// future model change becomes a `.lightweight(fromVersion:toVersion:)` entry.
enum IndexMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [IndexSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
