import Foundation
import HealthKit
import SwiftData

/// Observable HealthKit bridge. Reads 14 quantity / category / workout
/// types from Apple Health and writes bodyMass only. Lifetime:
/// instantiated once at app launch in IndexApp with the shared
/// ModelContainer (audit H10 — service mints contexts internally
/// instead of receiving one via side-channel mutation from a view).
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
    var isBackfilling = false
    var latestBodyFat: (percent: Double, date: Date)? = nil
    var latestLeanMass: (kg: Double, date: Date)? = nil
    var bodyFatHistory: [(date: Date, percent: Double)] = []
    var leanMassHistory: [(date: Date, kg: Double)] = []

    // MARK: - Ignored injected state
    //
    // ModelContainer is passed at construction (audit H10) so the
    // service can mint a context internally rather than receiving one
    // via side-channel mutation from a view's `.task`. The internal
    // accessor uses `mainContext` because every caller is already on
    // @MainActor (the service is wholesale @MainActor-isolated).

    @ObservationIgnored let modelContainer: ModelContainer
    @ObservationIgnored private var ctx: ModelContext { modelContainer.mainContext }
    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var workoutAnchor: HKQueryAnchor? = nil

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Capability check

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Type sets

    private var readTypes: Set<HKObjectType> {
        let types: Set<HKObjectType> = [
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
                await bootstrap()
            }
        } catch {
            print("[HealthKitService] requestAuthorization error: \(error)")
        }
    }

    /// App-launch entry point. If the user has already granted HK
    /// authorization in a previous session, refresh state, run the
    /// workout backfill, and arm the observers. Safe to call on every
    /// launch — the underlying fetches/upserts are idempotent and the
    /// anchored workout observer dedups via ±2 min predicate.
    func bootstrapIfAuthorized() async {
        guard Self.isAvailable else { return }
        let status = store.authorizationStatus(for: HKQuantityType(.bodyMass))
        guard status == .sharingAuthorized else { return }
        isAuthorized = true
        await bootstrap()
    }

    /// Fan-out triggered after first auth grant or on every cold start
    /// once authorized. Caller is responsible for the .sharingAuthorized
    /// check.
    private func bootstrap() async {
        await fetchAll()
        await fetchDailyHealth()

        // One-time historical backfill — covers everything from January 1
        // of the current year up to now, regardless of the anchored
        // observer's state. Without this, the user only sees workouts
        // *after* the moment they granted HK auth.
        if !UserDefaults.standard.bool(forKey: Self.didBackfillKey) {
            await importHistoricalWorkouts(since: Self.startOfCurrentYear())
            UserDefaults.standard.set(true, forKey: Self.didBackfillKey)
        }

        await importWorkouts()
        startObservingBodyMass()
        startObservingWorkouts()
    }

    private static func startOfCurrentYear() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year], from: .now)
        return cal.date(from: comps) ?? .now
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
        guard let bmSample = await fetchLatest(.bodyMass) else { return }
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
              UserDefaults.standard.object(forKey: Self.importWorkoutsKey) as? Bool ?? true else { return }

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

    /// One-time historical backfill. Walks HK from `startDate` to now via a
    /// plain HKSampleQuery (the anchored observer only returns workouts
    /// *since* its last fire, so it can't catch history that predates
    /// auth). Each match is processed through the normal pipeline —
    /// processHKWorkout's UUID dedup keeps a re-run idempotent.
    ///
    /// Surfaces progress via `isBackfilling` so the Fitness tab can show
    /// an "Importing your Apple Health workouts…" banner during the
    /// fetch. Backfill is gated by the `didHistoricalBackfill`
    /// UserDefaults flag in `bootstrap()` so this runs at most once per
    /// device install.
    func importHistoricalWorkouts(since startDate: Date) async {
        guard Self.isAvailable else { return }
        isBackfilling = true
        defer { isBackfilling = false }

        let workouts = await fetchHKWorkouts(since: startDate)
        for workout in workouts {
            await processHKWorkout(workout, context: ctx)
        }
    }

    func startObservingWorkouts() {
        guard Self.isAvailable else { return }
        workoutAnchor = loadWorkoutAnchor()

        // HKAnchoredObjectQuery's `resultsHandler` and `updateHandler` are
        // typed `@Sendable`. Marking the closure explicitly satisfies
        // Swift 6 strict concurrency. The closure only captures `self`
        // weakly, and all main-actor state access is gated through a
        // `Task { @MainActor in ... }` hop below.
        let handler: @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            [weak self] _, samples, _, newAnchor, error in
            guard error == nil else { return }
            Task { @MainActor in
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
                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else { return }
                for workout in workouts {
                    await self.processHKWorkout(workout, context: self.ctx)
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
    /// fixes applied. Dedup is two-tier:
    ///   1. Primary: HK UUID match — covers every re-import of an
    ///      auto-imported workout (anchored observer + historical
    ///      backfill).
    ///   2. Secondary: ±2-min date window — covers collisions with
    ///      manual logs and any legacy auto-imports created before the
    ///      hkWorkoutUUID field existed.
    /// Neither dedup predicate filters on `deletedFromIndex` — that's
    /// the tombstone contract that prevents swipe-deletes from being
    /// re-resurrected by future imports.
    private func processHKWorkout(_ workout: HKWorkout, context: ModelContext) async {
        let durationMin = Int(workout.duration / 60)
        guard durationMin >= 1 else { return }

        let uuidString = workout.uuid.uuidString
        let uuidDesc = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.hkWorkoutUUID == uuidString }
        )
        if !((try? context.fetch(uuidDesc)) ?? []).isEmpty { return }

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
            notes: "From Apple Health",
            hkWorkoutUUID: uuidString
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
        guard Self.isAvailable else { return }

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

    // MARK: - Write (instance method, async + throws — audit H4)

    /// Mirrors a manual weight entry to Apple Health. Throws when HK
    /// rejects the write (auth not granted for write, sample format
    /// invalid, store I/O error). Caller (LogWeightSheet) is expected
    /// to keep the local entry regardless and surface a banner on
    /// failure — DQ3 confirmed: Apple Health is a peer, not master.
    func saveWeight(kg: Double, date: Date) async throws {
        guard Self.isAvailable else {
            throw NSError(
                domain: "Index.HealthKitService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit isn't available on this device."]
            )
        }
        let type = HKQuantityType(.bodyMass)
        let qty = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: type, quantity: qty, start: date, end: date)
        try await store.save(sample)
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
    static let didBackfillKey = "didHistoricalBackfill"
}

// MARK: - Swim detail (HK swim workout enrichment)

/// Stroke styles surfaced to v2 callers — mirrors HKSwimmingStrokeStyle but
/// keeps HK types out of public API per the audit.
enum SwimStroke: String, Sendable {
    case freestyle, backstroke, breaststroke, butterfly, kickboard, mixed, unknown

    var label: String {
        switch self {
        case .freestyle:    "Freestyle"
        case .backstroke:   "Backstroke"
        case .breaststroke: "Breaststroke"
        case .butterfly:    "Butterfly"
        case .kickboard:    "Kickboard"
        case .mixed:        "Mixed"
        case .unknown:      "Unknown"
        }
    }
}

struct SwimHRSample: Sendable, Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let bpm: Double
}

struct SwimLength: Sendable, Identifiable {
    let id = UUID()
    let index: Int
    let stroke: SwimStroke
    let duration: TimeInterval
    let swolf: Int?
}

struct SwimSet: Sendable, Identifiable {
    let id = UUID()
    let index: Int
    let stroke: SwimStroke
    let distanceMeters: Double
    let swimDuration: TimeInterval
    let restDuration: TimeInterval
    let avgSWOLF: Double?
    let pacePer100m: TimeInterval
    let avgHR: Double?
}

struct SwimDetailData: Sendable {
    let hrSamples: [SwimHRSample]
    let avgSWOLF: Double?
    let sets: [SwimSet]
    let lengths: [SwimLength]
    /// Pool length in meters as detected from HKMetadataKeyLapLength
    /// (workout-level first, then per-lap fallback). Nil when neither
    /// source carried the metadata — the UI hides the Pool Length tile
    /// rather than guessing.
    let poolLengthMeters: Double?
}

extension HealthKitService {

    /// Looks up the HKWorkout by UUID, then enriches it with HR samples
    /// and HKWorkoutEvent lap data (per-length stroke + SWOLF). Returns
    /// nil if HK can't find the workout (manual entry has no HK record;
    /// HK auth was revoked since import; sample was deleted from Health).
    ///
    /// Caller (WorkoutDetailView) is expected to gate this on
    /// `session.type == .swimming && session.source == .healthkit`.
    func fetchSwimDetail(forWorkoutUUID uuidString: String) async -> SwimDetailData? {
        guard Self.isAvailable, let uuid = UUID(uuidString: uuidString) else { return nil }

        // 1. Find the HKWorkout by UUID.
        let workoutPred = HKQuery.predicateForObject(with: uuid)
        let workout: HKWorkout? = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: workoutPred,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, _ in
                cont.resume(returning: samples?.first as? HKWorkout)
            }
            store.execute(q)
        }
        guard let workout else { return nil }

        // 2. HR samples within the workout window.
        let hrSamples: [SwimHRSample] = await fetchHRSamples(start: workout.startDate, end: workout.endDate)
            .map {
                SwimHRSample(
                    date: $0.startDate,
                    bpm: $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                )
            }

        // 3. Lap events. Watch swim workouts emit one .lap event per
        //    pool length swum, with stroke-style + SWOLF in metadata.
        let lapEvents = (workout.workoutEvents ?? []).filter { $0.type == .lap }

        // Pool length detection — workout-level metadata first (where
        // Apple Health usually puts it), then per-lap fallback. Nil
        // when neither source has it; surfaced on SwimDetailData so the
        // UI can hide the Pool Length tile (per spec: don't display a
        // guess). For internal grouping math we still default to 25m
        // so the per-set distance figures remain sensible.
        let detectedPoolLength: Double? = {
            if let q = workout.metadata?[HKMetadataKeyLapLength] as? HKQuantity {
                return q.doubleValue(for: .meter())
            }
            for ev in lapEvents {
                if let q = ev.metadata?[HKMetadataKeyLapLength] as? HKQuantity {
                    return q.doubleValue(for: .meter())
                }
            }
            return nil
        }()
        let poolLengthForGrouping: Double = detectedPoolLength ?? 25

        var lengths: [SwimLength] = []
        for (i, event) in lapEvents.enumerated() {
            let strokeRaw = (event.metadata?[HKMetadataKeySwimmingStrokeStyle] as? NSNumber)?.intValue ?? 0
            let strokeHK  = HKSwimmingStrokeStyle(rawValue: strokeRaw) ?? .unknown
            let stroke    = mapStroke(strokeHK)
            let swolf     = (event.metadata?[HKMetadataKeySWOLFScore] as? NSNumber)?.intValue
            lengths.append(SwimLength(
                index: i + 1,
                stroke: stroke,
                duration: event.dateInterval.duration,
                swolf: swolf
            ))
        }

        // 4. Group sequential same-stroke lengths into sets. Stroke
        //    change → new set (per spec). Track the underlying lap
        //    events so we can compute set start/end + rest gaps.
        struct Bucket {
            let stroke: SwimStroke
            var lengths: [SwimLength]
            var lapEvents: [HKWorkoutEvent]
        }
        var buckets: [Bucket] = []
        for (i, len) in lengths.enumerated() {
            let event = lapEvents[i]
            if let lastIdx = buckets.indices.last, buckets[lastIdx].stroke == len.stroke {
                buckets[lastIdx].lengths.append(len)
                buckets[lastIdx].lapEvents.append(event)
            } else {
                buckets.append(Bucket(stroke: len.stroke, lengths: [len], lapEvents: [event]))
            }
        }

        // 5. Materialize SwimSet rows.
        var sets: [SwimSet] = []
        for (idx, bucket) in buckets.enumerated() {
            let distance = poolLengthForGrouping * Double(bucket.lengths.count)
            let swimDur  = bucket.lapEvents.reduce(0.0) { $0 + $1.dateInterval.duration }

            let swolfVals = bucket.lengths.compactMap(\.swolf).map(Double.init)
            let avgSwolf: Double? = swolfVals.isEmpty
                ? nil
                : swolfVals.reduce(0, +) / Double(swolfVals.count)

            // Rest duration = gap from this set's last lap end to the
            // next set's first lap start. Last set has no following
            // rest, so 0.
            let restDur: TimeInterval
            if idx + 1 < buckets.count,
               let thisEnd  = bucket.lapEvents.last?.dateInterval.end,
               let nextStart = buckets[idx + 1].lapEvents.first?.dateInterval.start {
                restDur = max(0, nextStart.timeIntervalSince(thisEnd))
            } else {
                restDur = 0
            }

            let pace100: TimeInterval = distance > 0 ? swimDur * 100.0 / distance : 0

            // Avg HR within the set's swim window.
            let avgHR: Double? = {
                guard let setStart = bucket.lapEvents.first?.dateInterval.start,
                      let setEnd   = bucket.lapEvents.last?.dateInterval.end else { return nil }
                let inSet = hrSamples.filter { $0.date >= setStart && $0.date <= setEnd }
                guard !inSet.isEmpty else { return nil }
                return inSet.reduce(0.0) { $0 + $1.bpm } / Double(inSet.count)
            }()

            sets.append(SwimSet(
                index: idx + 1,
                stroke: bucket.stroke,
                distanceMeters: distance,
                swimDuration: swimDur,
                restDuration: restDur,
                avgSWOLF: avgSwolf,
                pacePer100m: pace100,
                avgHR: avgHR
            ))
        }

        // Overall avg SWOLF across all lengths that carry the metadata.
        let allSWOLF = lengths.compactMap(\.swolf).map(Double.init)
        let overallSWOLF: Double? = allSWOLF.isEmpty
            ? nil
            : allSWOLF.reduce(0, +) / Double(allSWOLF.count)

        return SwimDetailData(
            hrSamples: hrSamples,
            avgSWOLF: overallSWOLF,
            sets: sets,
            lengths: lengths,
            poolLengthMeters: detectedPoolLength
        )
    }

    private func mapStroke(_ hk: HKSwimmingStrokeStyle) -> SwimStroke {
        switch hk {
        case .unknown:      return .unknown
        case .mixed:        return .mixed
        case .freestyle:    return .freestyle
        case .backstroke:   return .backstroke
        case .breaststroke: return .breaststroke
        case .butterfly:    return .butterfly
        case .kickboard:    return .kickboard
        @unknown default:   return .unknown
        }
    }
}
