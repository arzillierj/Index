import Foundation
import SwiftData

/// Barcode-keyed product cache. Upserted on every scan; useCount + lastUsed
/// drive a future "frequently eaten" surface.
@Model
final class FoodProduct {
    var barcode: String = ""
    var name: String = ""
    var brand: String = ""
    var kcalPer100g: Double = 0
    var proteinPer100g: Double = 0
    var carbsPer100g: Double = 0
    var fatPer100g: Double = 0
    var lastUsed: Date = Date.now
    var useCount: Int = 0

    init(
        barcode: String = "",
        name: String = "",
        brand: String = "",
        kcalPer100g: Double = 0,
        proteinPer100g: Double = 0,
        carbsPer100g: Double = 0,
        fatPer100g: Double = 0,
        lastUsed: Date = .now,
        useCount: Int = 0
    ) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.kcalPer100g = kcalPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.lastUsed = lastUsed
        self.useCount = useCount
    }

    func macros(forGrams g: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let r = g / 100.0
        return (kcalPer100g * r, proteinPer100g * r, carbsPer100g * r, fatPer100g * r)
    }

    var displayName: String { name.isEmpty ? "Unknown product" : name }
}
