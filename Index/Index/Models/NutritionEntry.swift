import Foundation
import SwiftData

enum MealType: String, CaseIterable, Codable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
}

enum NutritionSource: String, CaseIterable, Codable {
    case manual, barcode, photo
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
    /// True when the entry was created via the photo-to-macros flow. UI
    /// surfaces a "Photo estimate" badge for these rows.
    var photoEstimated: Bool = false
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
