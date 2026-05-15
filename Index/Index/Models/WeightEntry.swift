import Foundation
import SwiftData

/// Where the WeightEntry came from. RENPHO writes through HealthKit, so the
/// HK-write path must check the sample's HKSource bundle id to distinguish
/// .renpho from a generic .healthkit write.
enum WeightSource: String, CaseIterable, Codable {
    case manual, healthkit, renpho
}

@Model
final class WeightEntry {
    var date: Date = Date.now
    var weightKg: Double = 0
    var bodyFatPercent: Double = 0
    var hasBodyFat: Bool = false
    var leanMassKg: Double = 0
    var hasLeanMass: Bool = false
    var notes: String = ""
    var sourceRaw: String = WeightSource.manual.rawValue
    /// HK dedup predicates intentionally do NOT filter on this flag — that's
    /// how swipe-deletes act as tombstones against re-import.
    var deletedFromIndex: Bool = false
    /// HK sample UUID for auto-imported (HealthKit / RENPHO via HK)
    /// weight entries. Primary dedup key in
    /// HealthKitService.handleNewBodyMass — preferred over the ±5-min
    /// date window once populated. nil for manual entries (`source =
    /// .manual`) and for any auto-imports created before this field
    /// existed (pre-2026-05-15). The date-window fallback handles
    /// those legacy rows.
    var hkSampleUUID: String? = nil

    init(
        date: Date = .now,
        weightKg: Double = 0,
        bodyFatPercent: Double = 0,
        hasBodyFat: Bool = false,
        leanMassKg: Double = 0,
        hasLeanMass: Bool = false,
        notes: String = "",
        source: WeightSource = .manual,
        deletedFromIndex: Bool = false,
        hkSampleUUID: String? = nil
    ) {
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.hasBodyFat = hasBodyFat
        self.leanMassKg = leanMassKg
        self.hasLeanMass = hasLeanMass
        self.notes = notes
        self.sourceRaw = source.rawValue
        self.deletedFromIndex = deletedFromIndex
        self.hkSampleUUID = hkSampleUUID
    }

    var source: WeightSource {
        get { WeightSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
