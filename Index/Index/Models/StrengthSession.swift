import Foundation
import SwiftData

@Model
final class StrengthSession {
    /// Stable id used by WorkoutSession.strengthSessionId for the cross-link.
    var id: String = UUID().uuidString
    var date: Date = Date.now
    var endDate: Date = Date.now
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ExercisePerformance.session)
    var performances: [ExercisePerformance]? = []

    init(
        id: String = UUID().uuidString,
        date: Date = .now,
        endDate: Date = .now,
        notes: String = "",
        performances: [ExercisePerformance]? = []
    ) {
        self.id = id
        self.date = date
        self.endDate = endDate
        self.notes = notes
        self.performances = performances
    }

    var orderedPerformances: [ExercisePerformance] {
        (performances ?? []).sorted { $0.order < $1.order }
    }

    var durationSeconds: Int {
        max(0, Int(endDate.timeIntervalSince(date)))
    }

    var durationMinutes: Int {
        Int((Double(durationSeconds) / 60.0).rounded())
    }

    var isInProgress: Bool {
        endDate <= date
    }
}
