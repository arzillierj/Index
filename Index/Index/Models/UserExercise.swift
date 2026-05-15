import Foundation
import SwiftData

enum ExerciseKind: String, CaseIterable, Codable, Identifiable {
    case free, machine, bodyweight, assisted

    var id: String { rawValue }

    var caption: String {
        switch self {
        case .free:       "FREE WEIGHT"
        case .machine:    "MACHINE"
        case .bodyweight: "BODYWEIGHT"
        case .assisted:   "ASSISTED"
        }
    }

    /// True when load is *added* to bodyweight (or subtracted, for assisted).
    var isBodyweightAnchored: Bool {
        self == .bodyweight || self == .assisted
    }
}

struct ExerciseDefinition: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: ExerciseKind
    let defaultRestSeconds: Int
}

/// The 10 starter exercises the user picks from during onboarding (up to 5).
/// DECISION: scope-cut from v0's 40-exercise catalog. Custom exercises are out
/// of v1 entirely. Muscle-group grouping is not needed at a 5-exercise cap.
enum ExerciseCatalog {
    static let starter: [ExerciseDefinition] = [
        .init(id: "bench-press",    name: "Bench Press",    kind: .free,       defaultRestSeconds: 120),
        .init(id: "squat",          name: "Squat",          kind: .free,       defaultRestSeconds: 180),
        .init(id: "deadlift",       name: "Deadlift",       kind: .free,       defaultRestSeconds: 180),
        .init(id: "overhead-press", name: "Overhead Press", kind: .free,       defaultRestSeconds: 120),
        .init(id: "bent-over-row",  name: "Bent-Over Row",  kind: .free,       defaultRestSeconds: 120),
        .init(id: "pull-up",        name: "Pull-up",        kind: .bodyweight, defaultRestSeconds: 90),
        .init(id: "dip",            name: "Dip",            kind: .bodyweight, defaultRestSeconds: 90),
        .init(id: "lat-pulldown",   name: "Lat Pulldown",   kind: .machine,    defaultRestSeconds: 90),
        .init(id: "leg-press",      name: "Leg Press",      kind: .machine,    defaultRestSeconds: 120),
        .init(id: "cable-row",      name: "Cable Row",      kind: .machine,    defaultRestSeconds: 90),
    ]

    static func byId(_ id: String) -> ExerciseDefinition? {
        starter.first { $0.id == id }
    }
}

@Model
final class UserExercise {
    var id: String = UUID().uuidString
    var name: String = ""
    var kindRaw: String = ExerciseKind.free.rawValue
    var defaultRestSeconds: Int = 90
    var displayOrder: Int = 0
    // DEPRECATED: 2026-05-15 — never read or written by any view or
    // service. Field stays per the schema rules; no callers remain.
    var notes: String = ""
    /// Soft-hide marker for the user's library list (audit DQ4).
    /// True means the row is excluded from StrengthLibraryView and
    /// ExercisePickerSheet, but old session history still resolves
    /// the exercise name via ExercisePerformance.userExerciseId →
    /// UserExercise.id (both queries see hidden rows). Re-adding the
    /// same catalog id from AddExerciseSheet flips this back to false
    /// rather than inserting a duplicate row.
    var hiddenFromLibrary: Bool = false

    init(
        id: String = UUID().uuidString,
        name: String = "",
        kind: ExerciseKind = .free,
        defaultRestSeconds: Int = 90,
        displayOrder: Int = 0,
        notes: String = "",
        hiddenFromLibrary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.defaultRestSeconds = defaultRestSeconds
        self.displayOrder = displayOrder
        self.notes = notes
        self.hiddenFromLibrary = hiddenFromLibrary
    }

    var kind: ExerciseKind {
        get { ExerciseKind(rawValue: kindRaw) ?? .free }
        set { kindRaw = newValue.rawValue }
    }

    static func fromCatalog(_ def: ExerciseDefinition, displayOrder: Int = 0) -> UserExercise {
        UserExercise(
            id: def.id,
            name: def.name,
            kind: def.kind,
            defaultRestSeconds: def.defaultRestSeconds,
            displayOrder: displayOrder
        )
    }
}
