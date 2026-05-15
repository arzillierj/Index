import Foundation
import SwiftData

@Model
final class StrengthSession {
    /// Stable id used by WorkoutSession.strengthSessionId for the cross-link.
    var id: String = UUID().uuidString
    var date: Date = Date.now
    var endDate: Date = Date.now
    var notes: String = ""
    /// Whether the session is still being logged (audit H16 — replaces
    /// the previous `endDate <= date` heuristic, which returned true
    /// for exactly-equal timestamps and so could lie about
    /// in-progress state right after a same-tick endSession() call).
    /// Set false in ActiveStrengthSessionView.endSession when the
    /// real end-of-session is committed. Default true so a freshly-
    /// inserted session is correctly classified before its first
    /// `setupOnAppear` mutation.
    var inProgress: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \ExercisePerformance.session)
    var performances: [ExercisePerformance]? = []

    init(
        id: String = UUID().uuidString,
        date: Date = .now,
        endDate: Date = .now,
        notes: String = "",
        inProgress: Bool = true,
        performances: [ExercisePerformance]? = []
    ) {
        self.id = id
        self.date = date
        self.endDate = endDate
        self.notes = notes
        self.inProgress = inProgress
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

    /// Reads the explicit `inProgress` flag (audit H16). Pre-H16 rows
    /// migrated in with the default `true`; that's correct semantically
    /// — every committed historical session was completed and so
    /// would already have had its endDate stamped past `date`.
    /// Specifically, ActiveStrengthSessionView.endSession will start
    /// setting `inProgress = false` for new sessions; existing rows
    /// stay `inProgress = true` after migration but never need to be
    /// queried as "active" since they're not the current session.
    var isInProgress: Bool { inProgress }
}
