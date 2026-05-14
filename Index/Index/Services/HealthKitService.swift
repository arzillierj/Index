import Foundation
import HealthKit
import SwiftData

/// Observable HealthKit bridge. Reads 14 quantity / category / workout
/// types from Apple Health and writes bodyMass only. Lifetime: instantiated
/// once at app launch (BodyView keeps the @State); `modelContext` is set
/// before any import call.
///
/// v0 audit fixes baked in:
///   1. Anchor advance is gated on `hk_import_workouts` toggle — samples
///      delivered while toggle is off are NOT stranded forever.
///   2. activeEnergyBurned read on every auto-imported workout (kcalBurned
///      was dropped in v0's pre-fix processHKWorkout).
///   3. maxHeartRate captured from HR samples in the workout window.
///   4. RENPHO weigh-ins carry the leanMass sample into the WeightEntry,
///      and `WeightEntry.source = .renpho` when the HKSource bundle id
///      or name matches.
///   5. Distance read permissions present so workout.statistics(for:)
///      returns non-nil for cycling / walking-running / swimming.
@Observable
@MainActor
final class HealthKitService {

    // MARK: - Published state

    var isAuthorized = false
    var latestBodyFat: (percent: Double, date: Date)? = nil
    var latestLeanMass: (kg: Double, date: Date)? = nil
    var bodyFatHistory: [(date: Date, percent: Double)] = []
    var leanMassHistory: [(date: Date, kg: Double)] = []

    // MARK: - Ignored injected state

    @ObservationIgnored var modelContext: ModelContext? = nil
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var workoutAnchor: HKQueryAnchor? = nil

    // MARK: - Capability check

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Type sets

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.leanBodyMass),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.vo2Max),
            HKQuantityType(.restingHeartRate),
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.cyclingPower),
        ]
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        [HKQuantityType(.bodyMass)]
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard Self.isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = store.authorizationStatus(for: HKQuantityType(.bodyMass)) == .sharingAuthorized
            if isAuthorized {
                await fetchAll()
                await fetchDailyHealth()
                startObservingBodyMass()
                startObservingWorkouts()
            }
        } catch {
            print("[HealthKitService] requestAuthorization error: \(error)")
        }
    }

    // MARK: - Latest + history (body composition)

    func fetchAll() async {
        guard Self.isAvailable else { return }
        if let s = await fetchLatest(.bodyFatPercentage) {
            latestBodyFat = (
                percent: s.quantity.doubleValue(for: .percent()) * 100,
                date: s.startDate
            )
        }
        if let s = await fetchLatest(.leanBodyMass) {
            latestLeanMass = (
                kg: s.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                date: s.startDate
            )
        }
        bodyFatHistory = await fetchHistory(.bodyFatPercentage, days: 90)
            .map { (date: $0.startDate, percent: $0.quantity.doubleValue(for: .percent()) * 100) }
        leanMassHistory = await fetchHistory(.leanBodyMass, days: 90)
            .map { (date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    // MARK: - Body mass observer

    func startObservingBodyMass() {
        guard Self.isAvailable else { return }
        let type = HKQuantityType(.bodyMass)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
            guard error == nil else { return }
            Task { @MainActor in
                await self?.handleNewBodyMass()
            }
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
    }

    /// Combines bodyMass + bodyFatPercentage + leanBodyMass samples from
    /// the same time window AND the same HK source into one WeightEntry,
    /// tagging the source as `.renpho` if the bodyMass sample originated
    /// from a RENPHO app. Dedup window is ±5 min.
    ///
    /// Source-matching is required for body composition grouping: a
    /// RENPHO weigh-in shouldn't absorb a stale body-fat sample from
    /// another app that happens to fall in the ±5 min window, and a
    /// manual Index weight write shouldn't accidentally pick up a
    /// RENPHO body-fat reading. The published `latestBodyFat` /
    /// `latestLeanMass` tuples still take the most-recent reading from
    /// any source (they drive the Body screen's display).
    private func handleNewBodyMass() async {
        guard let ctx = modelContext,
              let bmSample = await fetchLatest(.bodyMass) else { return }
        let kg = bmSample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        let date = bmSample.startDate
        let source = detectWeightSource(bmSample)
        let bmBundleId = bmSample.sourceRevision.source.bundleIdentifier

        // Always refresh the published "latest" tuples — they're for
        // display and want the freshest reading regardless of source.
        if let fs = await fetchLatest(.bodyFatPercentage) {
            latestBodyFat = (
                percent: fs.quantity.doubleValue(for: .percent()) * 100,
                date: fs.startDate
            )
        }
        if let ls = await fetchLatest(.leanBodyMass) {
            latestLeanMass = (
                kg: ls.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                date: ls.startDate
            )
        }

        // For the WeightEntry grouping, require the body composition
        // samples to come from the same HK source as the bodyMass sample.
        var fatPct: Double? = nil
        var leanKg: Double? = nil
        let window: TimeInterval = 300

        if let fs = await fetchSampleNear(
            .bodyFatPercentage,
            date: date,
            window: window,
            fromSourceBundleId: bmBundleId
        ) {
            fatPct = fs.quantity.doubleValue(for: .percent()) * 100
        }
        if let ls = await fetchSampleNear(
            .leanBodyMass,
            date: date,
            window: window,
            fromSourceBundleId: bmBundleId
        ) {
            leanKg = ls.quantity.doubleValue(for: .gramUnit(with: .kilo))
        }

        // Dedup against existing WeightEntry rows within ±5 min. Predicate
        // intentionally does NOT filter on deletedFromIndex — that's how
        // swipe-deletes act as tombstones against re-import.
        let dedupeStart = date.addingTimeInterval(-window)
        let dedupeEnd   = date.addingTimeInterval(window)
        let desc = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date >= dedupeStart && $0.date <= dedupeEnd }
        )
        guard ((try? ctx.fetch(desc)) ?? []).isEmpty else { return }

        let entry = WeightEntry(
            date: date,
            weightKg: kg,
            bodyFatPercent: fatPct ?? 0,
            hasBodyFat: fatPct != nil,
            leanMassKg: leanKg ?? 0,
            hasLeanMass: leanKg != nil,
            source: source
        )
        ctx.insert(entry)
    }

    /// Finds the most recent sample of `id` within ±`window` of `date`
    /// that came from the given source bundle id. Used by
    /// handleNewBodyMass to group body composition samples to the
    /// matching weigh-in.
    private func fetchSampleNear(
        _ id: HKQuantityTypeIdentifier,
        date: Date,
        window: TimeInterval,
        fromSourceBundleId bundleId: String
    ) async -> HKQuantitySample? {
        let type = HKQuantityType(id)
        let start = date.addingTimeInterval(-window)
        let end   = date.addingTimeInterval(window)
        let timePred = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: timePred,
                limit: 10, sortDescriptors: [sort]
            ) { _, s, _ in
                cont.resume(returning: s as? [HKQuantitySample] ?? [])
            }
            store.execute(q)
        }
        return samples.first { $0.sourceRevision.source.bundleIdentifier == bundleId }
    }

    /// Reads the bodyMass sample's source revision to decide whether the
    /// weight came through HK from RENPHO specifically or from a generic
    /// app (Apple Health, third-party). Bundle id form on the App Store
    /// varies (com.renpho.RenphoHealth, com.qnniu.renpho, etc.), so match
    /// against both bundle id and source name case-insensitively.
    private func detectWeightSource(_ sample: HKSample) -> WeightSource {
        let id = sample.sourceRevision.source.bundleIdentifier.lowercased()
        let name = sample.sourceRevision.source.name.lowercased()
        if id.contains("renpho") || name.contains("renpho") { return .renpho }
        return .healthkit
    }

    // MARK: - Workout import (initial backfill + anchored observer)

    func importWorkouts() async {
        guard Self.isAvailable,
              UserDefaults.standard.object(forKey: Self.importWorkoutsKey) as? Bool ?? true,
              let ctx = modelContext else { return }

        let cutoff: Date = {
            if let last = UserDefaults.standard.object(forKey: Self.lastWorkoutSyncKey) as? Date {
                return last
            }
            return Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        }()

        let workouts = await fetchHKWorkouts(since: cutoff)
        for workout in workouts {
            await processHKWorkout(workout, context: ctx)
        }
        UserDefaults.standard.set(Date.now, forKey: Self.lastWorkoutSyncKey)
    }

    func startObservingWorkouts() {
        guard Self.isAvailable else { return }
        workoutAnchor = loadWorkoutAnchor()

        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            [weak self] _, samples, _, newAnchor, error in
            guard let self, error == nil else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // ANCHOR-GATING FIX (v0 audit). Do NOT advance the anchor if
                // the import toggle is off. Otherwise samples delivered in
                // the off-window are permanently skipped — turning the
                // toggle back on tomorrow won't re-deliver them.
                let toggleOn = UserDefaults.standard.object(forKey: Self.importWorkoutsKey) as? Bool ?? true
                guard toggleOn else { return }
                if let newAnchor {
                    self.workoutAnchor = newAnchor
                    self.saveWorkoutAnchor(newAnchor)
                }
                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty,
                      let ctx = self.modelContext else { return }
                for workout in workouts {
                    await self.processHKWorkout(workout, context: ctx)
                }
            }
        }

        let query = HKAnchoredObjectQuery(
            type: HKObjectType.workoutType(),
            predicate: nil,
            anchor: workoutAnchor,
            limit: HKObjectQueryNoLimit,
            resultsHandler: handler
        )
        query.updateHandler = handler
        store.execute(query)
    }

    private func fetchHKWorkouts(since cutoff: Date) async -> [HKWorkout] {
        let pred = HKQuery.predicateForSamples(withStart: cutoff, end: nil, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: pred,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(q)
        }
    }

    /// Maps the HKWorkout into a WorkoutSession with all of the v0 audit
    /// fixes applied. Dedup window is ±2 min, predicate unfiltered on
    /// deletedFromIndex (tombstone behavior).
    private func processHKWorkout(_ workout: HKWorkout, context: ModelContext) async {
        let durationMin = Int(workout.duration / 60)
        guard durationMin >= 1 else { return }

        let wStart = workout.startDate
        let wEnd   = workout.endDate
        let dedupeStart = wStart.addingTimeInterval(-120)
        let dedupeEnd   = wStart.addingTimeInterval(120)
        let desc = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= dedupeStart && $0.date <= dedupeEnd }
        )
        guard ((try? context.fetch(desc)) ?? []).isEmpty else { return }

        let type = mapWorkoutType(workout.workoutActivityType)

        // Distance — first non-nil sum across cycling / walk-run / swim types.
        var distanceKm = 0.0
        var hasDistance = false
        for distId: HKQuantityTypeIdentifier in [.distanceCycling, .distanceWalkingRunning, .distanceSwimming] {
            if let q = workout.statistics(for: HKQuantityType(distId))?.sumQuantity() {
                let v = q.doubleValue(for: .meterUnit(with: .kilo))
                if v > 0 {
                    distanceKm = v
                    hasDistance = true
                    break
                }
            }
        }

        let avgHR = await fetchAvgHeartRate(start: wStart, end: wEnd)
        let maxHR = await fetchMaxHeartRate(start: wStart, end: wEnd)

        // FIX: kcalBurned was dropped in v0's pre-fix processHKWorkout.
        // Workout.statistics(for: activeEnergyBurned) gives the active
        // energy total over the workout window.
        let kcal: Double? = workout
            .statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())

        context.insert(WorkoutSession(
            date: wStart,
            type: type,
            durationMinutes: durationMin,
            kcalBurned: kcal ?? 0,
            hasKcal: kcal != nil,
            avgHeartRate: avgHR ?? 0,
            hasHeartRate: avgHR != nil,
            maxHeartRate: maxHR ?? 0,
            hasMaxHeartRate: maxHR != nil,
            distanceKm: distanceKm,
            hasDistance: hasDistance,
            source: .healthkit,
            notes: "From Apple Health"
        ))
    }

    /// v2-corrected mapping. Differences from v0:
    ///   - hiking maps to .other (different MET than running)
    ///   - yoga / pilates map to .other (don't drive MPS like strength)
    ///   - tennis / badminton / racquetball / tableTennis map to .other
    ///   - rowing / elliptical / stairs / stepTraining map to .other
    private func mapWorkoutType(_ hk: HKWorkoutActivityType) -> WorkoutType {
        switch hk {
        case .cycling:
            return .cycling
        case .running, .walking:
            return .running
        case .swimming, .swimBikeRun:
            return .swimming
        case .squash:
            return .squash
        case .traditionalStrengthTraining,
             .functionalStrengthTraining,
             .crossTraining,
             .highIntensityIntervalTraining,
             .coreTraining:
            return .strength
        default:
            return .other
        }
    }

    // MARK: - HR helpers

    private func fetchAvgHeartRate(start: Date, end: Date) async -> Int? {
        let samples = await fetchHRSamples(start: start, end: end)
        guard !samples.isEmpty else { return nil }
        let bps = HKUnit.count().unitDivided(by: .second())
        let avg = samples.reduce(0.0) { $0 + $1.quantity.doubleValue(for: bps) } / Double(samples.count)
        return Int(avg * 60)
    }

    private func fetchMaxHeartRate(start: Date, end: Date) async -> Int? {
        let samples = await fetchHRSamples(start: start, end: end)
        guard !samples.isEmpty else { return nil }
        let bps = HKUnit.count().unitDivided(by: .second())
        let maxBps = samples.map { $0.quantity.doubleValue(for: bps) }.max() ?? 0
        return maxBps > 0 ? Int(maxBps * 60) : nil
    }

    private func fetchHRSamples(start: Date, end: Date) async -> [HKQuantitySample] {
        let type = HKQuantityType(.heartRate)
        let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, s, _ in
                cont.resume(returning: s as? [HKQuantitySample] ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: - Daily health vitals (HRV, VO2 max, resting HR)

    /// Foreground fetch on app open. Apple Watch writes each of these at
    /// most once per day, so polling on launch is sufficient — no
    /// observer needed. Upserts a DailyHealthMetrics row keyed on
    /// today's startOfDay.
    func fetchDailyHealth() async {
        guard Self.isAvailable, let ctx = modelContext else { return }

        let hrvSample = await fetchLatest(.heartRateVariabilitySDNN)
        let vo2Sample = await fetchLatest(.vo2Max)
        let rhrSample = await fetchLatest(.restingHeartRate)

        let hrvMs: Double? = hrvSample?.quantity.doubleValue(for: .secondUnit(with: .milli))
        let vo2: Double? = {
            guard let s = vo2Sample else { return nil }
            let unit = HKUnit.literUnit(with: .milli).unitDivided(
                by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())
            )
            return s.quantity.doubleValue(for: unit)
        }()
        let rhr: Int? = {
            guard let s = rhrSample else { return nil }
            let bps = HKUnit.count().unitDivided(by: .second())
            return Int(s.quantity.doubleValue(for: bps) * 60)
        }()

        guard hrvMs != nil || vo2 != nil || rhr != nil else { return }

        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let desc = FetchDescriptor<DailyHealthMetrics>(
            predicate: #Predicate { $0.date >= today && $0.date < tomorrow }
        )
        let row: DailyHealthMetrics
        if let existing = ((try? ctx.fetch(desc)) ?? []).first {
            row = existing
        } else {
            row = DailyHealthMetrics(date: today)
            ctx.insert(row)
        }
        if let h = hrvMs { row.hrvMs = h; row.hasHRV = true }
        if let v = vo2   { row.vo2Max = v; row.hasVO2Max = true }
        if let r = rhr   { row.restingHeartRate = r; row.hasRestingHeartRate = true }
    }

    // MARK: - Write (static — called from LogWeightView)

    static func saveWeight(kg: Double, date: Date) {
        guard isAvailable else { return }
        let s = HKHealthStore()
        let type = HKQuantityType(.bodyMass)
        let qty = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: type, quantity: qty, start: date, end: date)
        s.save(sample) { _, _ in }
    }

    // MARK: - Anchor persistence

    private func loadWorkoutAnchor() -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: Self.workoutAnchorKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveWorkoutAnchor(_ anchor: HKQueryAnchor) {
        let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        UserDefaults.standard.set(data, forKey: Self.workoutAnchorKey)
    }

    // MARK: - Generic fetch helpers

    private func fetchLatest(_ id: HKQuantityTypeIdentifier) async -> HKQuantitySample? {
        let type = HKQuantityType(id)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(q)
        }
    }

    private func fetchHistory(_ id: HKQuantityTypeIdentifier, days: Int) async -> [HKQuantitySample] {
        let type = HKQuantityType(id)
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let pred = HKQuery.predicateForSamples(withStart: cutoff, end: nil, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: type, predicate: pred,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: - UserDefaults keys

    static let importWorkoutsKey = "hk_import_workouts"
    static let lastWorkoutSyncKey = "hk_last_workout_sync"
    static let workoutAnchorKey = "hk_workout_anchor"
}
