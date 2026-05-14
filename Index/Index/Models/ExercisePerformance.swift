import Foundation
import SwiftData

@Model
final class ExercisePerformance {
    var session: StrengthSession? = nil
    /// Links to UserExercise.id. Not a SwiftData relationship — the user's
    /// exercise library is independent of session history.
    var userExerciseId: String = ""
    var order: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.performance)
    var sets: [SetEntry]? = []

    init(
        session: StrengthSession? = nil,
        userExerciseId: String = "",
        order: Int = 0,
        sets: [SetEntry]? = []
    ) {
        self.session = session
        self.userExerciseId = userExerciseId
        self.order = order
        self.sets = sets
    }

    var orderedSets: [SetEntry] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    var topSetWeightKg: Double? {
        (sets ?? []).map(\.weightKg).max()
    }
}
