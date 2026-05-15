import Foundation
import SwiftData

/// One row per calendar day. Upsert key is `date` at startOfDay(local).
/// HK fetches HRV, VO2 max, and resting heart rate once per app open and
/// mutates the row in place.
///
/// **Property default for `date` is `.distantPast` deliberately** — see
/// the audit note below.
@Model
final class DailyHealthMetrics {
    /// The property default is intentionally a sentinel (`.distantPast`),
    /// NOT `Calendar.current.startOfDay(for: .now)`. SwiftData's
    /// lightweight migration uses the property default to back-fill the
    /// column on existing rows that don't carry it; an eager `.now`
    /// default would mean every back-filled row collapses to a single
    /// timestamp (the moment of the migration) and collides on the
    /// upsert key. The sentinel makes any latent migration obvious
    /// instead — a row dated 0001-01-01 is unmistakable.
    ///
    /// New rows always go through the explicit `init(date:)` from
    /// `HealthKitService.fetchDailyHealth` which passes the real
    /// startOfDay value, so this default is never observed in normal
    /// operation.
    var date: Date = Date.distantPast
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
