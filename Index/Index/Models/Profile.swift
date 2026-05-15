import Foundation
import SwiftData

// CloudKit shape: every property has a default, every relationship optional,
// no @Attribute(.unique). Same shape every model in this folder follows.

enum Sex: String, CaseIterable, Codable {
    case male, female

    var label: String {
        switch self {
        case .male:   "Male"
        case .female: "Female"
        }
    }
}

enum ActivityLevel: String, CaseIterable, Codable {
    case sedentary
    case lightlyActive
    case moderatelyActive
    case veryActive
    case extraActive

    // Harris-Benedict multiplier (McArdle 2010).
    var multiplier: Double {
        switch self {
        case .sedentary:        1.2
        case .lightlyActive:    1.375
        case .moderatelyActive: 1.55
        case .veryActive:       1.725
        case .extraActive:      1.9
        }
    }

    var label: String {
        switch self {
        case .sedentary:        "Sedentary"
        case .lightlyActive:    "Lightly active"
        case .moderatelyActive: "Moderately active"
        case .veryActive:       "Very active"
        case .extraActive:      "Extra active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary:        "Desk job, little exercise"
        case .lightlyActive:    "Light exercise 1–3 days/week"
        case .moderatelyActive: "Moderate exercise 3–5 days/week"
        case .veryActive:       "Hard exercise 6–7 days/week"
        case .extraActive:      "Physical job + daily training"
        }
    }
}

enum Goal: String, CaseIterable, Codable {
    case lose, maintain, gain

    var label: String {
        switch self {
        case .lose:     "Lose weight"
        case .maintain: "Maintain"
        case .gain:     "Gain weight"
        }
    }
}

enum Units: String, CaseIterable, Codable {
    case metric, imperial

    var label: String {
        switch self {
        case .metric:   "Metric (kg / cm)"
        case .imperial: "Imperial (lb / ft·in)"
        }
    }
}

enum Module: String, CaseIterable, Codable {
    case body, fitness, nutrition

    var label: String {
        switch self {
        case .body:      "Body"
        case .fitness:   "Fitness"
        case .nutrition: "Nutrition"
        }
    }

    var detail: String {
        switch self {
        case .body:      "Weight, body composition, vitals."
        case .fitness:   "Workouts, cycling, strength."
        case .nutrition: "Meals, macros, barcode scanning."
        }
    }
}

@Model
final class Profile {
    /// Stable identity from IdentityService. DevIdentityService stores a UUID;
    /// AppleSignInIdentityService stores the SIWA user identifier after enrollment.
    var userId: String = ""
    var name: String = ""
    var age: Int = 30
    var heightCm: Double = 175
    var sexRaw: String = Sex.male.rawValue
    var activityLevelRaw: String = ActivityLevel.moderatelyActive.rawValue
    var goalRaw: String = Goal.maintain.rawValue
    var targetWeightKg: Double = 0
    var hasTargetWeight: Bool = false
    var unitsRaw: String = Units.metric.rawValue
    /// JSON-encoded [String] of Module raw values.
    var enabledModulesJSON: String = #"["body","fitness","nutrition"]"#
    var calorieAdjustmentKcal: Double = 0
    var proteinTargetG: Double = 150
    /// SCHEMA: additive — added so the Goal section can expose an
    /// "Eat back workout calories" toggle. When false (default),
    /// MetricsEngine.dailyTargets ignores workout kcal entirely, so
    /// the daily calorie target stays flat regardless of activity.
    /// Default false because cutters (the most common careful tracker)
    /// should NOT eat back workout calories — the deficit IS the point.
    /// Existing rows automatically pick up false via SwiftData
    /// lightweight migration.
    var eatBackWorkoutCalories: Bool = false
    /// SCHEMA: additive — gates the "Log" toolbar button in BodyView.
    /// Default false because automated sources (RENPHO via Apple
    /// Health) are the primary write path; manual logging clutters
    /// the UI for users with a smart scale. The toggle is exposed in
    /// Settings → Manual logging. Existing rows backfill `false` via
    /// SwiftData lightweight migration. HealthKit auto-imports
    /// continue regardless; editing existing entries via
    /// WeightEntryDetailSheet is unaffected — the toggle only hides
    /// the create-new entry point.
    var manualWeightLoggingEnabled: Bool = false
    /// SCHEMA: additive — gates the "Log" toolbar button in
    /// FitnessMainView (and through it every manual workout sheet
    /// and the active strength session entry point). Same reasoning
    /// + same migration semantics as `manualWeightLoggingEnabled`:
    /// Apple Watch auto-imports are the primary write path; manual
    /// entry is off by default. WorkoutDetailView /
    /// StrengthSessionDetailView remain reachable for editing or
    /// deleting historical sessions.
    var manualFitnessLoggingEnabled: Bool = false
    var appleHealthAuthorized: Bool = false
    var onboardingCompleted: Bool = false
    var createdAt: Date = Date.now

    init(
        userId: String = "",
        name: String = "",
        age: Int = 30,
        heightCm: Double = 175,
        sex: Sex = .male,
        activityLevel: ActivityLevel = .moderatelyActive,
        goal: Goal = .maintain,
        targetWeightKg: Double = 0,
        hasTargetWeight: Bool = false,
        units: Units = .metric,
        enabledModules: Set<Module> = [.body, .fitness, .nutrition],
        calorieAdjustmentKcal: Double = 0,
        proteinTargetG: Double = 150,
        eatBackWorkoutCalories: Bool = false,
        manualWeightLoggingEnabled: Bool = false,
        manualFitnessLoggingEnabled: Bool = false,
        appleHealthAuthorized: Bool = false,
        onboardingCompleted: Bool = false,
        createdAt: Date = .now
    ) {
        self.userId = userId
        self.name = name
        self.age = age
        self.heightCm = heightCm
        self.sexRaw = sex.rawValue
        self.activityLevelRaw = activityLevel.rawValue
        self.goalRaw = goal.rawValue
        self.targetWeightKg = targetWeightKg
        self.hasTargetWeight = hasTargetWeight
        self.unitsRaw = units.rawValue
        self.enabledModulesJSON = Profile.encodeModules(enabledModules)
        self.calorieAdjustmentKcal = calorieAdjustmentKcal
        self.proteinTargetG = proteinTargetG
        self.eatBackWorkoutCalories = eatBackWorkoutCalories
        self.manualWeightLoggingEnabled = manualWeightLoggingEnabled
        self.manualFitnessLoggingEnabled = manualFitnessLoggingEnabled
        self.appleHealthAuthorized = appleHealthAuthorized
        self.onboardingCompleted = onboardingCompleted
        self.createdAt = createdAt
    }

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityLevelRaw) ?? .moderatelyActive }
        set { activityLevelRaw = newValue.rawValue }
    }

    var goal: Goal {
        get { Goal(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }

    var units: Units {
        get { Units(rawValue: unitsRaw) ?? .metric }
        set { unitsRaw = newValue.rawValue }
    }

    var enabledModules: Set<Module> {
        get {
            guard let data = enabledModulesJSON.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else {
                return [.body, .fitness, .nutrition]
            }
            return Set(arr.compactMap(Module.init(rawValue:)))
        }
        set { enabledModulesJSON = Profile.encodeModules(newValue) }
    }

    private static func encodeModules(_ s: Set<Module>) -> String {
        let arr = s.map(\.rawValue).sorted()
        guard let data = try? JSONEncoder().encode(arr),
              let str = String(data: data, encoding: .utf8) else {
            // Decode-failure fallback (in `var enabledModules` getter)
            // returns the full default set so a malformed blob doesn't
            // strand the user without modules. Keep encode failure
            // symmetric — `"[]"` would silently disable every module
            // on the next read, the opposite of the decode-side
            // intent. The literal here matches the JSONEncoder output
            // for `["body","fitness","nutrition"]` (sorted, no
            // whitespace) so the round-trip is byte-stable.
            return Self.defaultModulesJSON
        }
        return str
    }

    /// Stable JSON blob for the default-enabled module set
    /// (Body / Fitness / Nutrition). Used both as the
    /// `enabledModulesJSON` property default AND as the encode-failure
    /// fallback above so the two paths are symmetric.
    static let defaultModulesJSON = #"["body","fitness","nutrition"]"#
}
