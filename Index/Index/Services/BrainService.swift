import Foundation

/// One sentence of interpretation per module — body, fitness, nutrition.
/// `id` is stable per-rule so a future dismiss-state layer can key on it
/// (v0's per-day dismiss is not carried into v2; this field exists so it
/// can be added without changing call sites).
struct ModuleInsight: Identifiable, Sendable {
    let id: String
    let module: Module
    let message: String
}

/// Pure-static rule engine producing one ModuleInsight per module. Strict
/// templates over module data — no LLM, no free-form generation. Wraps
/// MetricsEngine but does not duplicate its math.
enum BrainService {

    // MARK: - Body

    /// First matching rule wins:
    ///   1. Trending toward target with usable ETA
    ///   2. HRV down >10% vs 7-day baseline
    ///   3. HRV up >10% vs 7-day baseline
    ///   4. Weight stable (14-day range < 0.5 kg)
    static func bodyInsight(
        profile: Profile,
        last14DaysWeight: [WeightEntry],
        last7DaysHealth: [DailyHealthMetrics]
    ) -> ModuleInsight? {
        if profile.hasTargetWeight,
           let line = trendingTowardTarget(profile: profile, weights: last14DaysWeight) {
            return ModuleInsight(id: "body.target_eta", module: .body, message: line)
        }
        if let pct = hrvTrendPct(last7DaysHealth: last7DaysHealth), pct < -10 {
            return ModuleInsight(
                id: "body.hrv_down",
                module: .body,
                message: "HRV down \(Int(-pct))% this week — consider lighter training."
            )
        }
        if let pct = hrvTrendPct(last7DaysHealth: last7DaysHealth), pct > 10 {
            return ModuleInsight(
                id: "body.hrv_up",
                module: .body,
                message: "HRV up \(Int(pct))% — recovery looks strong."
            )
        }
        if last14DaysWeight.count >= 7 {
            let weights = last14DaysWeight.map(\.weightKg)
            if let maxW = weights.max(), let minW = weights.min(), maxW - minW < 0.5 {
                return ModuleInsight(
                    id: "body.stable",
                    module: .body,
                    message: "Weight stable this fortnight."
                )
            }
        }
        return nil
    }

    // MARK: - Fitness

    /// First matching rule wins. Workouts are filtered to the relevant week
    /// window by the caller (`@Query` predicate already excludes
    /// `deletedFromIndex` for the HK-mirrored types — WorkoutSession,
    /// DailyHealthMetrics and WeightEntry. NutritionEntry's
    /// deletedFromIndex is deprecated.).
    static func fitnessInsight(
        thisWeekWorkouts: [WorkoutSession],
        lastWeekWorkouts: [WorkoutSession],
        last7DaysHealth: [DailyHealthMetrics]
    ) -> ModuleInsight? {
        let n = thisWeekWorkouts.count
        let lastN = lastWeekWorkouts.count
        let hrvDown = (hrvTrendPct(last7DaysHealth: last7DaysHealth) ?? 0) < -10

        if hrvDown, n >= 3 {
            return ModuleInsight(
                id: "fitness.hrv_recovery",
                module: .fitness,
                message: "HRV is down — your \(n) workouts this week may need a recovery day."
            )
        }
        if n >= 4 {
            return ModuleInsight(
                id: "fitness.strong_week",
                module: .fitness,
                message: "Strong week. \(n) sessions logged, recovery looks good."
            )
        }
        if n < 2, lastN >= 3 {
            return ModuleInsight(
                id: "fitness.quiet_week",
                module: .fitness,
                message: "Quiet week — \(n) sessions vs last week's \(lastN)."
            )
        }
        if (2...3).contains(n) {
            return ModuleInsight(
                id: "fitness.on_pace",
                module: .fitness,
                message: "On pace. \(n) sessions logged this week."
            )
        }
        return nil
    }

    // MARK: - Nutrition

    /// First matching rule wins. `targets` is the MetricsEngine output for
    /// today; the workout reasons live there so this method doesn't
    /// recompute them.
    static func nutritionInsight(
        profile: Profile,
        targets: DailyTargets,
        todayEntries: [NutritionEntry],
        recentEntries: [NutritionEntry],
        todaysWorkouts: [WorkoutSession]
    ) -> ModuleInsight? {
        if targets.workoutCalories > 0, let w = todaysWorkouts.first {
            return ModuleInsight(
                id: "nutrition.workout_adjustment",
                module: .nutrition,
                message: "+\(Int(targets.workoutCalories)) kcal target adjustment from today's \(workoutLabel(w.type))."
            )
        }
        if targets.trendCalories > 0 {
            return ModuleInsight(
                id: "nutrition.fast_loss",
                module: .nutrition,
                message: "+200 kcal buffer — you're losing fast this fortnight."
            )
        }
        if profile.calorieAdjustmentKcal > 0, lowProteinDays(targets: targets, recentEntries: recentEntries) >= 3 {
            return ModuleInsight(
                id: "nutrition.low_protein",
                module: .nutrition,
                message: "Protein under 80% of target for 3 days while cutting — muscle loss risk."
            )
        }
        if let gap = mealGapHours(todayEntries: todayEntries, recentEntries: recentEntries), gap >= 4 {
            return ModuleInsight(
                id: "nutrition.meal_gap",
                module: .nutrition,
                message: "You haven't eaten in \(Int(gap)) hours."
            )
        }
        return nil
    }

    // MARK: - Helpers

    private static func trendingTowardTarget(profile: Profile, weights: [WeightEntry]) -> String? {
        guard weights.count >= 7,
              let newest = weights.first, let oldest = weights.last else { return nil }
        let daySpan = newest.date.timeIntervalSince(oldest.date) / 86400
        guard daySpan > 0 else { return nil }
        let target = profile.targetWeightKg
        let distance = target - newest.weightKg

        if abs(distance) < 0.5 {
            return "At target weight — \(formatKg(target)) kg."
        }
        let totalChange = newest.weightKg - oldest.weightKg
        let dailyRate = totalChange / daySpan
        guard (distance < 0 && dailyRate < 0) || (distance > 0 && dailyRate > 0) else {
            return nil
        }
        let daysToTarget = distance / dailyRate
        guard daysToTarget > 0, daysToTarget < 365 else { return nil }
        let etaDate = Date.now.addingTimeInterval(daysToTarget * 86400)
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        let direction = totalChange < 0 ? "down" : "up"
        return "Trending \(direction) — on pace for \(formatKg(target)) kg by \(f.string(from: etaDate))."
    }

    /// Compare the latest HRV reading to the mean of the other readings in
    /// the last-7-days window. Returns nil if fewer than 3 samples have
    /// `hasHRV == true`. Positive % = HRV trending up.
    private static func hrvTrendPct(last7DaysHealth: [DailyHealthMetrics]) -> Double? {
        let samples = last7DaysHealth.filter { $0.hasHRV && $0.hrvMs > 0 }
        guard samples.count >= 3, let latest = samples.first?.hrvMs else { return nil }
        let rest = samples.dropFirst().map(\.hrvMs)
        let baseline = rest.reduce(0, +) / Double(rest.count)
        guard baseline > 0 else { return nil }
        return (latest - baseline) / baseline * 100
    }

    private static func lowProteinDays(targets: DailyTargets, recentEntries: [NutritionEntry]) -> Int {
        let cal = Calendar.current
        let now = Date.now
        var lowDays = 0
        for offset in 1...3 {
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now)),
                  let dayEnd = cal.date(byAdding: .day, value: 1, to: day) else { continue }
            let total = recentEntries
                .filter { $0.date >= day && $0.date < dayEnd }
                .reduce(0.0) { $0 + $1.protein }
            if total < targets.proteinBase * 0.8 { lowDays += 1 }
        }
        return lowDays
    }

    /// Hours since the last meal during waking hours (08:00–20:00 local).
    /// Falls back to "most recent meal across all history" when nothing
    /// was logged today — keeps the rule firing on an empty-today scenario.
    private static func mealGapHours(
        todayEntries: [NutritionEntry],
        recentEntries: [NutritionEntry]
    ) -> Double? {
        let cal = Calendar.current
        let now = Date.now
        let hour = cal.component(.hour, from: now)
        guard hour >= 8, hour <= 20 else { return nil }
        let lastToday = todayEntries
            .sorted(by: { $0.date < $1.date })
            .last
        let last = lastToday ?? recentEntries.first
        guard let last else { return nil }
        return now.timeIntervalSince(last.date) / 3600
    }

    private static func workoutLabel(_ t: WorkoutType) -> String {
        switch t {
        case .cycling:  "ride"
        case .running:  "run"
        case .swimming: "swim"
        case .strength: "strength session"
        case .squash:   "squash"
        case .other:    "workout"
        }
    }

    private static func formatKg(_ kg: Double) -> String {
        kg == floor(kg) ? "\(Int(kg))" : String(format: "%.1f", kg)
    }
}
