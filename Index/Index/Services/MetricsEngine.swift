import Foundation

/// Pure-static math + cross-module daily-target computation. No state, no
/// fetching — every caller passes `@Query` data in. The body-math functions
/// (BMI, BMR, TDEE, LBM, IBW) are ported verbatim from v0 with citations
/// preserved; only the wiring (field names, when called) is v2-shape.
enum MetricsEngine {

    // MARK: - Body math (ported verbatim from v0 BodyCalculations.swift)

    /// BMI = kg / m². WHO 1995 categories.
    static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let hm = heightCm / 100
        return weightKg / (hm * hm)
    }

    static func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5:     return "Underweight"
        case 18.5..<25.0: return "Healthy"
        case 25.0..<30.0: return "Overweight"
        default:          return "Obese"
        }
    }

    /// Mifflin-St Jeor 1990. Am J Clin Nutr 51(2):241-247.
    /// Male:   10W + 6.25H − 5A + 5
    /// Female: 10W + 6.25H − 5A − 161
    static func bmr(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5.0 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// TDEE = BMR × Harris-Benedict multiplier (McArdle 2010).
    static func tdee(bmr: Double, activityLevel: ActivityLevel) -> Double {
        bmr * activityLevel.multiplier
    }

    /// Boer 1984. J Appl Physiol 57(4):1186-1190.
    /// Male:   0.407W + 0.267H − 19.2
    /// Female: 0.252W + 0.473H − 48.3
    static func leanBodyMass(weightKg: Double, heightCm: Double, sex: Sex) -> Double {
        switch sex {
        case .male:   return 0.407 * weightKg + 0.267 * heightCm - 19.2
        case .female: return 0.252 * weightKg + 0.473 * heightCm - 48.3
        }
    }

    /// Devine 1974 ±10%. Drug Intell Clin Pharm 8:650-655.
    static func idealWeightRange(heightCm: Double, sex: Sex) -> ClosedRange<Double> {
        let hIn = heightCm / 2.54
        let ibw = (sex == .male ? 50.0 : 45.5) + 2.3 * max(0, hIn - 60)
        let lower = max(40, ibw * 0.9)
        return lower...max(lower + 1, ibw * 1.1)
    }

    // MARK: - Unit conversions

    static func kgToLbs(_ kg: Double) -> Double { kg * 2.20462 }
    static func lbsToKg(_ lbs: Double) -> Double { lbs / 2.20462 }
    static func cmToFtIn(_ cm: Double) -> String {
        let totalIn = Int(cm / 2.54)
        return "\(totalIn / 12)'\(totalIn % 12)\""
    }

    // MARK: - Cross-module daily targets

    /// Today's calorie + protein targets, with the reasons for any
    /// adjustments. Inputs are all read from existing @Query data; outputs
    /// are computed once per body evaluation and passed down by callers
    /// (don't access the computed property multiple times — see v0 audit M1).
    static func dailyTargets(
        profile: Profile,
        latestWeight: WeightEntry?,
        todaysWorkouts: [WorkoutSession],
        last14DaysWeight: [WeightEntry]
    ) -> DailyTargets {
        let weightKg = latestWeight?.weightKg
            ?? (profile.hasTargetWeight ? profile.targetWeightKg : 75)

        let bmrValue = bmr(
            weightKg: weightKg, heightCm: profile.heightCm,
            age: profile.age, sex: profile.sex
        )
        let tdeeValue = tdee(bmr: bmrValue, activityLevel: profile.activityLevel)
        // Signed adjustment: NEGATIVE = deficit (cutting), POSITIVE =
        // surplus (bulking), 0 = maintenance. Always ADD to TDEE so the
        // sign carries the direction. Pre-fix, the convention was
        // "positive number representing a deficit," which inverted the
        // user-visible slider on the Settings sheet. A one-time UD-
        // flagged migration in ContentView.task negates any existing
        // positive values from the old convention.
        let adjustment = profile.calorieAdjustmentKcal
        let safeFloor = max(1200, bmrValue * 1.1)

        // Base = TDEE + signed adjustment, never below safety floor.
        let caloriesBase = max(safeFloor, tdeeValue + adjustment)

        // Workout calories — Ainsworth 2011 MET values × bodyweight × hours.
        // DECISION: v2 doesn't track avg power, so the v0 "cycling vigorous
        // (avgWatts > 200) → 10.0 MET" bump can't apply. Cycling stays 7.0
        // always. Re-instate the bump if a power field is added to v2's
        // WorkoutSession in the future.
        let rawWorkoutKcal = todaysWorkouts.reduce(0.0) { sum, w in
            let met: Double
            switch w.type {
            case .cycling:  met = 7.0
            case .running:  met = 9.0
            case .swimming: met = 8.0
            case .squash:   met = 7.3
            case .strength, .other: met = 5.0
            }
            return sum + met * weightKg * (Double(w.durationMinutes) / 60.0)
        }
        // Gate the workout contribution on the eat-back toggle. When
        // false (default — cutter-safe), workouts don't lift the daily
        // calorie target; the deficit stays the deficit. Toggle on for
        // maintainers / bulkers who want activity-aware targets.
        let workoutContribution = profile.eatBackWorkoutCalories
            ? min(rawWorkoutKcal, 1000)
            : 0
        // `workoutCalories` on DailyTargets carries the post-gate value
        // so downstream view sites (caption, insight) only surface the
        // adjustment when it's actually applied.
        let workoutCalories = workoutContribution

        // Aggressive-loss buffer: 14-day weekly rate > 1%/week → +200 kcal.
        let trendCalories = aggressiveLossBuffer(last14DaysWeight: last14DaysWeight)

        var reasons: [String] = []
        if workoutCalories > 0 { reasons.append("+\(Int(workoutCalories)) kcal workout") }
        if trendCalories > 0   { reasons.append("+200 kcal (fast loss)") }
        let calorieAdjustmentReason: String? = reasons.isEmpty
            ? nil
            : reasons.joined(separator: " · ")

        let calories = caloriesBase + workoutCalories + trendCalories

        // Workout protein — Jäger 2017 + Helms 2014.
        // Strength: +0.4 g/kg
        // Endurance ≥60 min: +0.3 g/kg
        // Endurance <60 min: +0.2 g/kg
        // Squash ≥45 min: +0.3 g/kg, else +0.2 g/kg
        // Other: +0.2 g/kg
        // Cap workout bonus at 0.6 g/kg/day; cap final at 2.5 g/kg.
        var rawProteinAdd = 0.0
        for w in todaysWorkouts {
            switch w.type {
            case .strength:
                rawProteinAdd += 0.4 * weightKg
            case .cycling, .running, .swimming:
                rawProteinAdd += (w.durationMinutes >= 60 ? 0.3 : 0.2) * weightKg
            case .squash:
                rawProteinAdd += (w.durationMinutes >= 45 ? 0.3 : 0.2) * weightKg
            case .other:
                rawProteinAdd += 0.2 * weightKg
            }
        }
        let workoutProteinAdded = min(rawProteinAdd, 0.6 * weightKg)
        let proteinBase = profile.proteinTargetG
        let protein = min(proteinBase + workoutProteinAdded, 2.5 * weightKg)
        let proteinAdjustmentReason: String? = workoutProteinAdded > 1
            ? "+\(Int(workoutProteinAdded)) g protein for today's workout"
            : nil

        return DailyTargets(
            calories: calories,
            caloriesBase: caloriesBase,
            calorieAdjustmentReason: calorieAdjustmentReason,
            protein: protein,
            proteinBase: proteinBase,
            proteinAdjustmentReason: proteinAdjustmentReason,
            tdee: tdeeValue,
            deficit: adjustment,
            workoutCalories: workoutCalories,
            trendCalories: trendCalories,
            workoutProteinAdded: workoutProteinAdded
        )
    }

    private static func aggressiveLossBuffer(last14DaysWeight: [WeightEntry]) -> Double {
        guard last14DaysWeight.count >= 7,
              let newest = last14DaysWeight.first,
              let oldest = last14DaysWeight.last else { return 0 }
        let daySpan = newest.date.timeIntervalSince(oldest.date) / 86400
        guard daySpan > 0, oldest.weightKg > 0 else { return 0 }
        let weeklyRate = (oldest.weightKg - newest.weightKg) / oldest.weightKg * (7.0 / daySpan)
        return weeklyRate > 0.01 ? 200 : 0
    }
}

/// Cross-module daily targets. The view that owns the MetricsEngine call
/// passes this down to subviews — do NOT recompute per re-render.
struct DailyTargets: Sendable {
    let calories: Double
    let caloriesBase: Double
    let calorieAdjustmentReason: String?
    let protein: Double
    let proteinBase: Double
    let proteinAdjustmentReason: String?
    let tdee: Double
    let deficit: Double
    let workoutCalories: Double
    let trendCalories: Double
    let workoutProteinAdded: Double
}
