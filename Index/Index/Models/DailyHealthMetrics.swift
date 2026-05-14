import Foundation
import SwiftData

/// One row per calendar day. Upsert key is `date` at startOfDay(local).
/// HK fetches HRV, VO2 max, and resting heart rate once per app open and
/// mutates the row in place.
@Model
final class DailyHealthMetrics {
    var date: Date = Calendar.current.startOfDay(for: .now)
    var hrvMs: Double = 0
    var hasHRV: Bool = false
    var vo2Max: Double = 0
    var hasVO2Max: Bool = false
    var restingHeartRate: Int = 0
    var hasRestingHeartRate: Bool = false

    init(
        date: Date = Calendar.current.startOfDay(for: .now),
        hrvMs: Double = 0,
        hasHRV: Bool = false,
        vo2Max: Double = 0,
        hasVO2Max: Bool = false,
        restingHeartRate: Int = 0,
        hasRestingHeartRate: Bool = false
    ) {
        self.date = date
        self.hrvMs = hrvMs
        self.hasHRV = hasHRV
        self.vo2Max = vo2Max
        self.hasVO2Max = hasVO2Max
        self.restingHeartRate = restingHeartRate
        self.hasRestingHeartRate = hasRestingHeartRate
    }
}
