import SwiftData

/// Single source of truth for the model schema.
///
/// VersionedSchema entries were removed after V1/V2/V3 generated
/// "Duplicate version checksums detected" on launch. The previous design
/// had three VersionedSchema enums whose `.models` properties all
/// delegated to the same Swift class types — SwiftData computes a
/// shape-based checksum that collided across versions, since the
/// compile-time class definitions are singular per type. The proper
/// per-version snapshot pattern (nested @Model classes inside each
/// VersionedSchema) wasn't applied, and isn't worth introducing for
/// purely additive changes.
///
/// For purely additive changes (new field with a default, new @Model
/// type added to the list below), SwiftData's lightweight migration
/// diffs the stored shape against the current code and applies defaults
/// automatically. No VersionedSchema declaration needed. See
/// CLAUDE.md "Schema evolution rules" for what changes are allowed
/// and which require a different recovery path.
enum IndexSchema {
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
        ]
    }
}
