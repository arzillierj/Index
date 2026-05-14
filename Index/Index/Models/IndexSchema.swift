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

/// V2 — adds `intensity: Int` and `hasIntensity: Bool` to WorkoutSession so
/// manual log forms can record 1–5 perceived exertion. Strictly additive
/// with defaults; SwiftData handles the lightweight migration.
enum IndexSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        IndexSchemaV1.models
    }
}

/// V3 — adds `hkWorkoutUUID: String?` to WorkoutSession so auto-imports
/// dedup by the HK sample UUID rather than only by a ±2-minute date
/// window. Required for the historical Apple Health backfill: re-running
/// imports won't produce duplicate rows because each HKWorkout has a
/// stable UUID. Strictly additive (optional with nil default); SwiftData
/// handles the lightweight migration.
enum IndexSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        IndexSchemaV2.models
    }
}

/// Wired into the ModelContainer from day one. Every schema change becomes
/// a new VersionedSchema + a `.lightweight(fromVersion:toVersion:)` entry.
enum IndexMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [IndexSchemaV1.self, IndexSchemaV2.self, IndexSchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: IndexSchemaV1.self,
                toVersion: IndexSchemaV2.self
            ),
            .lightweight(
                fromVersion: IndexSchemaV2.self,
                toVersion: IndexSchemaV3.self
            ),
        ]
    }
}
