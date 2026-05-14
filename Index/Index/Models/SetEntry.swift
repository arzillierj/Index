import Foundation
import SwiftData

@Model
final class SetEntry {
    var performance: ExercisePerformance? = nil
    var order: Int = 0
    /// Added weight for bodyweight kinds; negative for assisted kinds.
    var weightKg: Double = 0
    var reps: Int = 0
    var completedAt: Date = Date.now

    init(
        performance: ExercisePerformance? = nil,
        order: Int = 0,
        weightKg: Double = 0,
        reps: Int = 0,
        completedAt: Date = .now
    ) {
        self.performance = performance
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.completedAt = completedAt
    }
}
