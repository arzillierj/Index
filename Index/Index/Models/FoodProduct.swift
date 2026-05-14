import Foundation
import SwiftData

/// Barcode-keyed product cache. Upserted on every scan; useCount + lastUsed
/// drive a future "frequently eaten" surface.
///
/// `unit` ("g" or "ml") records whether the product is solid or liquid so
/// the next scan of the same barcode defaults its quantity-input unit
/// correctly without re-hitting the OFF API or re-running detection.
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
    /// "g" for solids, "ml" for liquids. Detected from OFF
    /// product_quantity_unit / serving_quantity_unit, with a
    /// categories_tags fallback. Stored so cached scans skip detection.
    var unit: String = "g"

    init(
        barcode: String = "",
        name: String = "",
        brand: String = "",
        kcalPer100g: Double = 0,
        proteinPer100g: Double = 0,
        carbsPer100g: Double = 0,
        fatPer100g: Double = 0,
        lastUsed: Date = .now,
        useCount: Int = 0,
        unit: String = "g"
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
        self.unit = unit
    }

    func macros(forGrams g: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let r = g / 100.0
        return (kcalPer100g * r, proteinPer100g * r, carbsPer100g * r, fatPer100g * r)
    }

    var displayName: String { name.isEmpty ? "Unknown product" : name }
}

/// Lightweight value type passed from the OFF fetch into the result sheet.
/// Mirrors v0's `ScannedFood` plus a `unit` field for v2's g/ml detection.
struct ScannedFood: Sendable {
    var barcode: String
    var name: String
    var brand: String
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var unit: String = "g"

    func macros(forGrams g: Double) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        let r = g / 100.0
        return (kcalPer100g * r, proteinPer100g * r, carbsPer100g * r, fatPer100g * r)
    }
}
