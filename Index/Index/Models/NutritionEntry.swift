import Foundation
import SwiftData

enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch:     "Lunch"
        case .dinner:    "Dinner"
        case .snack:     "Snack"
        }
    }
}

enum NutritionSource: String, CaseIterable, Codable {
    case manual, barcode
    // DEPRECATED: 2026-05-15 — photo flow cut from v1 (see CLAUDE.md
    // "Things explicitly NOT in v1"). No code path ever produced a
    // NutritionEntry with source = .photo, but the case stays in the
    // enum so any persisted row that somehow reads back as `.photo`
    // still decodes (rather than falling through to the .manual
    // fallback in `var source` which would be silently misleading).
    case photo
}

@Model
final class NutritionEntry {
    var date: Date = Date.now
    var label: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var mealTypeRaw: String = MealType.snack.rawValue
    var sourceRaw: String = NutritionSource.manual.rawValue
    // DEPRECATED: 2026-05-15 — photo flow cut from v1; no code path
    // writes this field. Schema rules forbid deletion (lightweight
    // migration would otherwise drop the column on existing rows).
    // Field stays; nothing reads or writes it.
    var photoEstimated: Bool = false
    // DEPRECATED: 2026-05-15 — NutritionEntry never mirrored to HK so
    // the soft-delete-as-tombstone contract that protects WeightEntry /
    // WorkoutSession against HK re-import has nothing to protect here.
    // The swipe path uses `context.delete(entry)` (hard delete);
    // queries no longer filter on this field. Schema rules forbid
    // deletion of the column itself.
    var deletedFromIndex: Bool = false

    init(
        date: Date = .now,
        label: String = "",
        kcal: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        mealType: MealType = .snack,
        source: NutritionSource = .manual,
        photoEstimated: Bool = false,
        deletedFromIndex: Bool = false
    ) {
        self.date = date
        self.label = label
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.mealTypeRaw = mealType.rawValue
        self.sourceRaw = source.rawValue
        self.photoEstimated = photoEstimated
        self.deletedFromIndex = deletedFromIndex
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var source: NutritionSource {
        get { NutritionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
