import Foundation
import SwiftData

enum WorkoutType: String, CaseIterable, Codable, Identifiable {
    case cycling, running, swimming, strength, squash, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cycling:  "Cycling"
        case .running:  "Running"
        case .swimming: "Swimming"
        case .strength: "Strength"
        case .squash:   "Squash"
        case .other:    "Other"
        }
    }

    var icon: String {
        switch self {
        case .cycling:  "bicycle"
        case .running:  "figure.run"
        case .swimming: "figure.pool.swim"
        case .strength: "dumbbell.fill"
        case .squash:   "figure.squash"
        case .other:    "bolt.fill"
        }
    }
}

enum WorkoutSourceKind: String, CaseIterable, Codable {
    case manual, healthkit
}

@Model
final class WorkoutSession {
    var date: Date = Date.now
    var typeRaw: String = WorkoutType.other.rawValue
    var durationMinutes: Int = 0
    var kcalBurned: Double = 0
    var hasKcal: Bool = false
    var avgHeartRate: Int = 0
    var hasHeartRate: Bool = false
    var maxHeartRate: Int = 0
    var hasMaxHeartRate: Bool = false
    var distanceKm: Double = 0
    var hasDistance: Bool = false
    /// 1–5 perceived exertion; only meaningful when hasIntensity is true.
    /// HK auto-imported workouts leave hasIntensity = false — the Watch
    /// doesn't capture RPE.
    var intensity: Int = 0
    var hasIntensity: Bool = false
    var sourceRaw: String = WorkoutSourceKind.manual.rawValue
    var notes: String = ""
    /// Tombstone for HK auto-import dedup — predicates do NOT filter on this.
    var deletedFromIndex: Bool = false
    /// Soft link to StrengthSession.id when `type == .strength`. Empty otherwise.
    var strengthSessionId: String = ""
    /// HK sample UUID for auto-imported workouts. Primary dedup key in
    /// processHKWorkout — preferred over the ±2-min date window once
    /// populated. nil for manual entries and for any auto-imports
    /// created before this field existed (pre-V3).
    var hkWorkoutUUID: String? = nil

    init(
        date: Date = .now,
        type: WorkoutType = .other,
        durationMinutes: Int = 0,
        kcalBurned: Double = 0,
        hasKcal: Bool = false,
        avgHeartRate: Int = 0,
        hasHeartRate: Bool = false,
        maxHeartRate: Int = 0,
        hasMaxHeartRate: Bool = false,
        distanceKm: Double = 0,
        hasDistance: Bool = false,
        intensity: Int = 0,
        hasIntensity: Bool = false,
        source: WorkoutSourceKind = .manual,
        notes: String = "",
        deletedFromIndex: Bool = false,
        strengthSessionId: String = "",
        hkWorkoutUUID: String? = nil
    ) {
        self.date = date
        self.typeRaw = type.rawValue
        self.durationMinutes = durationMinutes
        self.kcalBurned = kcalBurned
        self.hasKcal = hasKcal
        self.avgHeartRate = avgHeartRate
        self.hasHeartRate = hasHeartRate
        self.maxHeartRate = maxHeartRate
        self.hasMaxHeartRate = hasMaxHeartRate
        self.distanceKm = distanceKm
        self.hasDistance = hasDistance
        self.intensity = intensity
        self.hasIntensity = hasIntensity
        self.sourceRaw = source.rawValue
        self.notes = notes
        self.deletedFromIndex = deletedFromIndex
        self.strengthSessionId = strengthSessionId
        self.hkWorkoutUUID = hkWorkoutUUID
    }

    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRaw) ?? .other }
        set { typeRaw = newValue.rawValue }
    }

    var source: WorkoutSourceKind {
        get { WorkoutSourceKind(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
