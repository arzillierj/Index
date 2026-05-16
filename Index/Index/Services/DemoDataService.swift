import Foundation
import SwiftData

/// Generates a believable rolling-year dataset into a SwiftData
/// context. Called once per demo store (gated by
/// `isSeeded(in:)`) from ContentView on the first launch into
/// demo mode. Idempotent only in the sense that the caller is
/// expected to check `isSeeded` first — running this twice would
/// insert a second year on top of the first.
///
/// The data must be **believable**: not a single flat ramp, not
/// every-day perfection. The generator uses a seeded RNG so the
/// dataset is stable across re-runs (same seed = same data) — the
/// generated weights / workouts / meals look the same every time
/// a developer wipes and regenerates the demo store, which is
/// useful for QA and screenshots.
///
/// What gets generated:
/// - One Profile (coherent: 32y male, 180cm, moderately active,
///   cut target 76kg).
/// - 10 UserExercise rows from `ExerciseCatalog.starter`.
/// - ~280 WeightEntry rows over 365 days, gentle downward trend
///   plus daily noise + occasional plateaus.
/// - ~150 WorkoutSession rows — clustered weeks, rest gaps,
///   mixed types (cycling, swimming, squash, running, strength).
///   All with HK-shape metadata (source = .healthkit, fake
///   hkWorkoutUUID, hasHeartRate = true with realistic
///   avg/max) so the HR chart path in WorkoutDetailView fires.
/// - ~25 StrengthSession rows with realistic sets/reps/weights
///   that progress slowly across the year.
/// - ~1200 NutritionEntry rows clustered across most days
///   (~3.5/day average), kcal/macros landing around the target.
/// - ~320 DailyHealthMetrics rows with HRV / VO2 / resting HR.
///
/// What is **deliberately not generated**: `AIUsageRecord`. The
/// AI cost ledger must only reflect real API spend (the Settings
/// "month-to-date spend" figure would lie if seeded). The demo
/// store stays at $0.00 AI spend forever, and `ClaudeService`
/// short-circuits all network calls when demo mode is on.
@MainActor
enum DemoDataService {

    // MARK: - Public surface

    /// Believable last-night sleep duration for the demo "Time
    /// asleep" tile. Returns a value in the 6h 20m – 8h 10m
    /// band that drifts day-to-day so reopening the demo doesn't
    /// always read the same number. Stable for a given calendar
    /// day (seeded by ordinal) so multiple Body screens within
    /// the same day are consistent. NOT seeded into HK — this
    /// is read directly by BodyView in demo mode so the view
    /// can stay HK-free in demo.
    static func lastNightSleepSeconds() -> TimeInterval {
        let cal = Calendar.current
        let dayOrdinal = cal.ordinality(of: .day, in: .era, for: .now) ?? 0
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(dayOrdinal)) &* 0xA5A5_A5A5)
        // Bias toward ~7h 15m with ±55 min variance — typical
        // adult range, not always perfectly 8h.
        let minutes = 6 * 60 + 20 + Int(rng.nextDouble(in: 0 ... 110))
        return TimeInterval(minutes * 60)
    }

    /// True when this store already has a Profile row. Used by
    /// ContentView to gate the seeding call — the demo store is
    /// generated once per file and persisted, not regenerated
    /// per launch.
    static func isSeeded(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Profile>()
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Seed the full demo dataset. Throws on save failure — the
    /// caller should surface a one-time warning if this fires.
    /// On a clean demo store this completes in well under a
    /// second on a modern device.
    static func seedFreshDataset(in context: ModelContext) throws {
        var rng = SeededRNG(seed: 0xC0FFEE_DEADBEEF)
        let today = Calendar.current.startOfDay(for: .now)

        let profile = makeProfile()
        context.insert(profile)

        let exercises = makeStarterExercises()
        for ex in exercises {
            context.insert(ex)
        }

        seedWeights(in: context, endingAt: today, rng: &rng)
        seedDailyMetrics(in: context, endingAt: today, rng: &rng)
        seedWorkouts(in: context, exercises: exercises, endingAt: today, rng: &rng)
        seedNutrition(in: context, profile: profile, endingAt: today, rng: &rng)

        try context.save()
    }

    // MARK: - Profile + starter exercises

    private static func makeProfile() -> Profile {
        Profile(
            userId: "demo-user",
            name: "Alex Bauer",
            age: 32,
            heightCm: 180,
            sex: .male,
            activityLevel: .moderatelyActive,
            goal: .lose,
            targetWeightKg: 76,
            hasTargetWeight: true,
            units: .metric,
            enabledModules: [.body, .fitness, .nutrition],
            calorieAdjustmentKcal: -300,
            proteinTargetG: 165,
            eatBackWorkoutCalories: false,
            manualWeightLoggingEnabled: false,
            manualFitnessLoggingEnabled: false,
            notifyOnNewWorkout: false,
            notifyOnNewWeight: false,
            appleHealthAuthorized: false,
            onboardingCompleted: true,
            createdAt: Calendar.current.date(byAdding: .day, value: -365, to: .now) ?? .now
        )
    }

    private static func makeStarterExercises() -> [UserExercise] {
        ExerciseCatalog.starter
            .enumerated()
            .map { i, def in UserExercise.fromCatalog(def, displayOrder: i) }
    }

    // MARK: - Weights
    //
    // ~280 entries over 365 days (5–6 per week with occasional
    // weeklong gaps). Start ~80.5 kg, end ~76.0 kg with gentle
    // downward drift, daily noise ±0.35 kg, two small plateaus
    // and one minor upward blip. Body-fat + lean mass set on
    // ~40% of entries to mirror RENPHO's coverage of the real
    // store (smart scale doesn't always read full composition).

    private static func seedWeights(
        in context: ModelContext,
        endingAt today: Date,
        rng: inout SeededRNG
    ) {
        let cal = Calendar.current
        let startWeight = 80.5
        let endWeight   = 76.1
        let days = 365

        for d in 0..<days {
            let date = cal.date(byAdding: .day, value: -(days - 1 - d), to: today) ?? today

            // Skip ~30% of days (missed weigh-ins). Cluster three
            // longer gaps into specific stretches so the chart has
            // realistic "no data" valleys instead of uniform noise.
            let inLongGap1 = (d >= 47 && d <= 53)   // travel
            let inLongGap2 = (d >= 188 && d <= 197) // illness
            let inLongGap3 = (d >= 295 && d <= 301) // forgot scale
            if inLongGap1 || inLongGap2 || inLongGap3 { continue }
            if rng.nextDouble() < 0.28 { continue }

            // Base trend — linear from start to end with two
            // plateaus that flatten the slope.
            let progress = Double(d) / Double(days - 1)
            var weight = startWeight + (endWeight - startWeight) * progress

            // Plateau at days 80-110 (cut held) and 250-280 (refeed).
            if d >= 80 && d <= 110 { weight += 0.4 }
            if d >= 250 && d <= 280 { weight += 0.7 }

            // Daily noise.
            weight += rng.nextDouble(in: -0.42 ... 0.42)

            // Add a small lunch-time vs. morning weigh-in
            // variation so timestamps don't all collapse to
            // midnight.
            let hour = Int(rng.nextDouble(in: 6 ... 9))
            let minute = Int(rng.nextDouble(in: 0 ... 59))
            let stampedDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date

            // ~40% of entries carry body-fat % + lean mass
            // (RENPHO coverage pattern). BF trends from ~17.5%
            // down to ~14.0%. Lean mass computed from weight.
            let hasComp = rng.nextDouble() < 0.40
            let bf = hasComp ? max(13.0, 17.5 - 3.5 * progress + rng.nextDouble(in: -0.4 ... 0.4)) : 0
            let lbm = hasComp ? weight * (1 - bf / 100) : 0

            let entry = WeightEntry(
                date: stampedDate,
                weightKg: weight,
                bodyFatPercent: bf,
                hasBodyFat: hasComp,
                leanMassKg: lbm,
                hasLeanMass: hasComp,
                notes: "",
                source: hasComp ? .renpho : .healthkit,
                deletedFromIndex: false,
                hkSampleUUID: "demo-weight-\(d)"
            )
            context.insert(entry)
        }
    }

    // MARK: - Daily health metrics
    //
    // ~320 rows over 365 days. HRV in a believable 38–72 ms band
    // with noise; VO2 max trending from 44 → 48 over the year as
    // fitness improves; resting HR slowly dropping 56 → 50 bpm.

    private static func seedDailyMetrics(
        in context: ModelContext,
        endingAt today: Date,
        rng: inout SeededRNG
    ) {
        let cal = Calendar.current
        let days = 365
        for d in 0..<days {
            // Skip ~12% — Watch occasionally misses a day.
            if rng.nextDouble() < 0.12 { continue }
            let date = cal.startOfDay(for: cal.date(byAdding: .day, value: -(days - 1 - d), to: today) ?? today)
            let progress = Double(d) / Double(days - 1)

            let hrv = 50.0 + 14.0 * sin(Double(d) / 9.0) + rng.nextDouble(in: -6 ... 6)
            let vo2 = 44.0 + 4.0 * progress + rng.nextDouble(in: -0.5 ... 0.5)
            let rhr = Int((56.0 - 6.0 * progress + rng.nextDouble(in: -2 ... 2)).rounded())

            let m = DailyHealthMetrics(
                date: date,
                hrvMs: max(28, hrv),
                hasHRV: true,
                vo2Max: vo2,
                hasVO2Max: true,
                restingHeartRate: max(44, rhr),
                hasRestingHeartRate: true
            )
            context.insert(m)
        }
    }

    // MARK: - Workouts
    //
    // ~150 sessions over 365 days, clustered. The day-by-day
    // pass coin-flips activity based on a sliding "training
    // intensity" parameter — heavy weeks make 5 sessions likely,
    // light weeks make 1, gap weeks make 0. Mix of types per
    // template; each session has HK-shape metadata so the
    // workout-detail screen renders the HR chart via the demo-
    // mode procedural generator in WorkoutDetailView.

    private struct WorkoutTemplate {
        let type: WorkoutType
        let durationRange: ClosedRange<Int>
        let kcalPerMin: ClosedRange<Double>
        let avgHRRange: ClosedRange<Int>
        let maxHROffset: ClosedRange<Int>
        let distanceKmRange: ClosedRange<Double>?
        let hasDistance: Bool
    }

    private static let templates: [WorkoutTemplate] = [
        .init(type: .cycling,  durationRange: 35 ... 95, kcalPerMin: 7.0 ... 9.5,
              avgHRRange: 128 ... 152, maxHROffset: 18 ... 32,
              distanceKmRange: 12 ... 38, hasDistance: true),
        .init(type: .running,  durationRange: 22 ... 55, kcalPerMin: 9.0 ... 12.5,
              avgHRRange: 142 ... 168, maxHROffset: 12 ... 22,
              distanceKmRange: 4 ... 11, hasDistance: true),
        .init(type: .swimming, durationRange: 30 ... 60, kcalPerMin: 8.0 ... 11.0,
              avgHRRange: 130 ... 155, maxHROffset: 14 ... 24,
              distanceKmRange: 1.0 ... 2.4, hasDistance: true),
        .init(type: .squash,   durationRange: 45 ... 75, kcalPerMin: 9.5 ... 13.0,
              avgHRRange: 145 ... 168, maxHROffset: 14 ... 26,
              distanceKmRange: nil, hasDistance: false),
    ]

    private static func seedWorkouts(
        in context: ModelContext,
        exercises: [UserExercise],
        endingAt today: Date,
        rng: inout SeededRNG
    ) {
        let cal = Calendar.current
        let days = 365

        // Strength is its own scheduling pass — twice a week on
        // average, distributed evenly. Other workouts use the
        // template pool with a per-day probability that tracks a
        // sine wave (training cycle blocks ~6 weeks).
        var strengthCounter = 0

        for d in 0..<days {
            let dayOffset = -(days - 1 - d)
            let date = cal.date(byAdding: .day, value: dayOffset, to: today) ?? today
            let progress = Double(d) / Double(days - 1)

            // Long gaps — two illness/travel weeks.
            if d >= 47 && d <= 53 { continue }
            if d >= 188 && d <= 197 { continue }

            // Per-day "should I train?" probability, biased by a
            // slow 6-week-period sine wave (training blocks of
            // hard / easy weeks).
            let cycle = 0.50 + 0.18 * sin(Double(d) / 9.5)

            if rng.nextDouble() < cycle {
                // Bias type by day-of-week for a believable
                // weekly routine. Monday-ish runs, mid-week
                // squash, weekend cycling.
                let weekday = cal.component(.weekday, from: date) // 1=Sun ... 7=Sat
                let template: WorkoutTemplate = {
                    switch weekday {
                    case 1, 7: return templates[0] // Sun/Sat — cycling
                    case 2:    return templates[1] // Mon — running
                    case 3, 5: return templates[3] // Tue/Thu — squash
                    case 4:    return templates[2] // Wed — swimming
                    default:
                        return templates[Int(rng.nextDouble() * Double(templates.count)) % templates.count]
                    }
                }()
                insertGenericWorkout(template: template, on: date, progress: progress, rng: &rng, in: context)
            }

            // Strength roughly twice per week — fire on Tue + Fri
            // when not in a gap window. Skip occasional weeks.
            let weekday = cal.component(.weekday, from: date)
            if (weekday == 3 || weekday == 6), rng.nextDouble() < 0.78 {
                insertStrengthWorkout(
                    exercises: exercises,
                    on: date,
                    progress: progress,
                    sessionIndex: strengthCounter,
                    rng: &rng,
                    in: context
                )
                strengthCounter += 1
            }
        }
    }

    private static func insertGenericWorkout(
        template: WorkoutTemplate,
        on day: Date,
        progress: Double,
        rng: inout SeededRNG,
        in context: ModelContext
    ) {
        let cal = Calendar.current
        let hour = Int(rng.nextDouble(in: 7 ... 19))
        let minute = Int(rng.nextDouble(in: 0 ... 59))
        let start = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day

        let duration = Int(rng.nextDouble(in: Double(template.durationRange.lowerBound) ... Double(template.durationRange.upperBound)))
        let kcalPerMin = rng.nextDouble(in: template.kcalPerMin)
        let avgHR = Int(rng.nextDouble(in: Double(template.avgHRRange.lowerBound) ... Double(template.avgHRRange.upperBound)))
        let maxHR = avgHR + Int(rng.nextDouble(in: Double(template.maxHROffset.lowerBound) ... Double(template.maxHROffset.upperBound)))
        let kcal = Double(duration) * kcalPerMin

        let distanceKm: Double
        if let r = template.distanceKmRange {
            distanceKm = rng.nextDouble(in: r)
        } else {
            distanceKm = 0
        }

        let workout = WorkoutSession(
            date: start,
            type: template.type,
            durationMinutes: duration,
            kcalBurned: kcal,
            hasKcal: true,
            avgHeartRate: avgHR,
            hasHeartRate: true,
            maxHeartRate: maxHR,
            hasMaxHeartRate: true,
            distanceKm: distanceKm,
            hasDistance: template.hasDistance,
            intensity: 0,
            hasIntensity: false,
            source: .healthkit,
            notes: "",
            deletedFromIndex: false,
            strengthSessionId: "",
            hkWorkoutUUID: "demo-\(template.type.rawValue)-\(Int(start.timeIntervalSince1970))"
        )
        context.insert(workout)
    }

    private static func insertStrengthWorkout(
        exercises: [UserExercise],
        on day: Date,
        progress: Double,
        sessionIndex: Int,
        rng: inout SeededRNG,
        in context: ModelContext
    ) {
        let cal = Calendar.current
        let hour = Int(rng.nextDouble(in: 17 ... 20))
        let minute = Int(rng.nextDouble(in: 0 ... 59))
        let start = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        let durationMin = Int(rng.nextDouble(in: 40 ... 75))
        let end = start.addingTimeInterval(TimeInterval(durationMin * 60))

        // Three to five exercises per session, sampled from the
        // user's library. Use a deterministic rotation across
        // sessions so the same exercises cluster realistically.
        let exerciseCount = 3 + (sessionIndex % 3)
        let rotated = Array(exercises.shuffled(using: &rng).prefix(exerciseCount))

        let strength = StrengthSession(
            id: "demo-strength-\(sessionIndex)",
            date: start,
            endDate: end,
            notes: "",
            inProgress: false
        )
        context.insert(strength)

        for (perfIdx, ex) in rotated.enumerated() {
            let perf = ExercisePerformance(
                session: strength,
                userExerciseId: ex.id,
                order: perfIdx
            )
            context.insert(perf)

            // Three to four sets per exercise. Weights progress
            // from a per-exercise baseline up over the year.
            let setCount = 3 + (rng.nextDouble() < 0.5 ? 0 : 1)
            let baseWeight = baseStrengthWeight(for: ex.id)
            let progressedBase = baseWeight + (baseWeight * 0.15 * progress)
            for setIdx in 0..<setCount {
                let setWeight = max(0, progressedBase + rng.nextDouble(in: -2.5 ... 2.5))
                let reps = 6 + Int(rng.nextDouble(in: 0 ... 4))
                let setEntry = SetEntry(
                    performance: perf,
                    order: setIdx,
                    weightKg: setWeight,
                    reps: reps,
                    completedAt: start.addingTimeInterval(TimeInterval((perfIdx * 8 + setIdx * 2) * 60))
                )
                context.insert(setEntry)
            }
        }

        // Mirror the strength session into a WorkoutSession so it
        // shows up in the Fitness feed.
        let mirror = WorkoutSession(
            date: start,
            type: .strength,
            durationMinutes: durationMin,
            kcalBurned: Double(durationMin) * 5.5,
            hasKcal: true,
            avgHeartRate: 112,
            hasHeartRate: true,
            maxHeartRate: 138,
            hasMaxHeartRate: true,
            distanceKm: 0,
            hasDistance: false,
            intensity: 0,
            hasIntensity: false,
            source: .healthkit,
            notes: "",
            deletedFromIndex: false,
            strengthSessionId: strength.id,
            hkWorkoutUUID: "demo-strength-\(sessionIndex)"
        )
        context.insert(mirror)
    }

    private static func baseStrengthWeight(for exerciseId: String) -> Double {
        switch exerciseId {
        case "bench-press":    return 80
        case "squat":          return 110
        case "deadlift":       return 130
        case "overhead-press": return 50
        case "bent-over-row":  return 70
        case "pull-up":        return 0      // bodyweight
        case "dip":            return 0      // bodyweight
        case "lat-pulldown":   return 65
        case "leg-press":      return 160
        case "cable-row":      return 60
        default: return 50
        }
    }

    // MARK: - Nutrition
    //
    // Most days populated, 3–4 entries each (breakfast, lunch,
    // dinner, sometimes a snack). Calorie totals land near the
    // profile's target (1900-ish for a 32y male cutter at -300
    // adjustment), with day-to-day variation. Food labels drawn
    // from a fixed pool so the FREQUENT chips look real.

    private struct DemoFood {
        let label: String
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let mealType: MealType
    }

    private static let foodPool: [DemoFood] = [
        // Breakfasts
        .init(label: "Greek yogurt bowl",     kcal: 320, protein: 28, carbs: 35, fat: 8,  mealType: .breakfast),
        .init(label: "Oatmeal + banana",      kcal: 410, protein: 14, carbs: 72, fat: 7,  mealType: .breakfast),
        .init(label: "Scrambled eggs + toast", kcal: 480, protein: 28, carbs: 38, fat: 22, mealType: .breakfast),
        .init(label: "Protein smoothie",      kcal: 350, protein: 40, carbs: 28, fat: 6,  mealType: .breakfast),
        .init(label: "Whey + oats",           kcal: 380, protein: 35, carbs: 48, fat: 6,  mealType: .breakfast),

        // Lunches
        .init(label: "Chicken rice bowl",     kcal: 620, protein: 48, carbs: 70, fat: 12, mealType: .lunch),
        .init(label: "Tuna salad",            kcal: 410, protein: 36, carbs: 18, fat: 22, mealType: .lunch),
        .init(label: "Salmon + quinoa",       kcal: 580, protein: 42, carbs: 50, fat: 18, mealType: .lunch),
        .init(label: "Beef wrap",             kcal: 560, protein: 38, carbs: 48, fat: 20, mealType: .lunch),
        .init(label: "Pasta + chicken",       kcal: 640, protein: 42, carbs: 78, fat: 14, mealType: .lunch),
        .init(label: "Risotto",               kcal: 590, protein: 22, carbs: 78, fat: 18, mealType: .lunch),

        // Dinners
        .init(label: "Steak + sweet potato",  kcal: 720, protein: 52, carbs: 52, fat: 28, mealType: .dinner),
        .init(label: "Chicken stir-fry",      kcal: 580, protein: 44, carbs: 56, fat: 14, mealType: .dinner),
        .init(label: "Salmon + asparagus",    kcal: 540, protein: 42, carbs: 22, fat: 28, mealType: .dinner),
        .init(label: "Bolognese",             kcal: 680, protein: 38, carbs: 72, fat: 22, mealType: .dinner),
        .init(label: "Thai green curry",      kcal: 620, protein: 36, carbs: 58, fat: 26, mealType: .dinner),
        .init(label: "Roast chicken + veg",   kcal: 560, protein: 48, carbs: 32, fat: 22, mealType: .dinner),

        // Snacks
        .init(label: "Whey isolate",          kcal: 120, protein: 25, carbs: 3,  fat: 1,  mealType: .snack),
        .init(label: "Apple + peanut butter", kcal: 210, protein: 5,  carbs: 28, fat: 10, mealType: .snack),
        .init(label: "Cottage cheese",        kcal: 180, protein: 24, carbs: 8,  fat: 6,  mealType: .snack),
        .init(label: "Almonds",               kcal: 170, protein: 6,  carbs: 6,  fat: 14, mealType: .snack),
        .init(label: "Protein bar",           kcal: 220, protein: 20, carbs: 22, fat: 7,  mealType: .snack),
        .init(label: "Banana",                kcal: 105, protein: 1,  carbs: 27, fat: 0,  mealType: .snack),
    ]

    private static func seedNutrition(
        in context: ModelContext,
        profile: Profile,
        endingAt today: Date,
        rng: inout SeededRNG
    ) {
        let cal = Calendar.current
        let days = 365

        let breakfasts = foodPool.filter { $0.mealType == .breakfast }
        let lunches    = foodPool.filter { $0.mealType == .lunch }
        let dinners    = foodPool.filter { $0.mealType == .dinner }
        let snacks     = foodPool.filter { $0.mealType == .snack }

        for d in 0..<days {
            let date = cal.date(byAdding: .day, value: -(days - 1 - d), to: today) ?? today

            // Skip ~9% of days entirely (didn't log). Skip the
            // long gaps (matching the workout/weight gaps).
            if d >= 47 && d <= 53 { continue }
            if d >= 188 && d <= 197 { continue }
            if rng.nextDouble() < 0.09 { continue }

            insertMeal(pool: breakfasts, on: date, hour: 7, minute: 30, rng: &rng, in: context)
            insertMeal(pool: lunches,    on: date, hour: 12, minute: 45, rng: &rng, in: context)
            insertMeal(pool: dinners,    on: date, hour: 19, minute: 30, rng: &rng, in: context)

            // ~50% of days get a snack.
            if rng.nextDouble() < 0.5 {
                insertMeal(pool: snacks, on: date, hour: 15, minute: 30, rng: &rng, in: context)
            }
            // Some heavy days get a second snack.
            if rng.nextDouble() < 0.18 {
                insertMeal(pool: snacks, on: date, hour: 21, minute: 30, rng: &rng, in: context)
            }
        }
    }

    private static func insertMeal(
        pool: [DemoFood],
        on day: Date,
        hour: Int,
        minute: Int,
        rng: inout SeededRNG,
        in context: ModelContext
    ) {
        let cal = Calendar.current
        let idx = Int(rng.nextDouble() * Double(pool.count)) % pool.count
        let food = pool[idx]
        // Add ±20-minute jitter so timestamps don't all land on
        // the half hour.
        let jitter = Int(rng.nextDouble(in: -20 ... 20))
        let stamped = cal.date(bySettingHour: hour, minute: max(0, min(59, minute + jitter)), second: 0, of: day) ?? day

        // ±10% kcal/macro variation per entry so the FREQUENT
        // chips' labels stay constant but the numbers feel real.
        let scale = rng.nextDouble(in: 0.90 ... 1.12)
        let entry = NutritionEntry(
            date: stamped,
            label: food.label,
            kcal: (food.kcal * scale).rounded(),
            protein: (food.protein * scale).rounded(),
            carbs: (food.carbs * scale).rounded(),
            fat: (food.fat * scale).rounded(),
            mealType: food.mealType,
            source: .manual,
            photoEstimated: false,
            deletedFromIndex: false
        )
        context.insert(entry)
    }
}

// MARK: - Seeded RNG

/// Tiny deterministic RNG (xorshift64-star). Used so the demo
/// dataset is **stable** across re-generations — wipe the demo
/// store and regenerate, the same weights and workouts come
/// back. This matters for screenshots, QA, and for not
/// surprising the user when they reset demo data.
///
/// Not cryptographic. Conforms to `RandomNumberGenerator` so
/// Swift's `.shuffled(using:)` and friends work directly.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid the all-zeros lock state of xorshift.
        self.state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 0x2545F4914F6CDD1D
    }

    mutating func nextDouble() -> Double {
        // Uniform in [0, 1). High 53 bits → Double mantissa.
        Double(next() >> 11) * (1.0 / Double(1 << 53))
    }

    mutating func nextDouble(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + nextDouble() * (range.upperBound - range.lowerBound)
    }
}
