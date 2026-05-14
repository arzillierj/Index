import Foundation

enum OFFError: Error {
    case notFound
    case networkError(Error)
    case malformedResponse
}

/// Verbatim port of the v0 service at
///   /Users/yannis/Dashboard/Dashboard/Dashboard/Services/OpenFoodFactsService.swift
/// — same JSONSerialization-based dictionary walk, same `n()` coercion,
/// same status check, same throwing surface.
///
/// Only two changes vs v0:
///   1. Language-preferred name (en/de/fr/it before product_name).
///   2. Unit detection (g vs ml) applied AFTER the fetch via `detectUnit`,
///      kept structurally separate from the parser per the port spec.
struct OpenFoodFactsService {
    static func fetch(barcode: String) async throws -> ScannedFood {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        var request = URLRequest(url: url)
        request.setValue("IndexApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let data: Data
        do {
            let (d, _) = try await URLSession.shared.data(for: request)
            data = d
        } catch {
            throw OFFError.networkError(error)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 1,
              let product = json["product"] as? [String: Any]
        else {
            throw OFFError.notFound
        }

        let name = (product["product_name_en"] as? String)?.nilIfEmpty
            ?? (product["product_name_de"] as? String)?.nilIfEmpty
            ?? (product["product_name_fr"] as? String)?.nilIfEmpty
            ?? (product["product_name_it"] as? String)?.nilIfEmpty
            ?? (product["product_name"] as? String)
            ?? ""
        let brand = (product["brands"] as? String) ?? ""
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]

        func n(_ key: String) -> Double {
            (nutriments[key] as? Double) ?? (nutriments[key] as? Int).map(Double.init) ?? 0
        }

        var food = ScannedFood(
            barcode: barcode,
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            kcalPer100g: n("energy-kcal_100g"),
            proteinPer100g: n("proteins_100g"),
            carbsPer100g: n("carbohydrates_100g"),
            fatPer100g: n("fat_100g")
        )
        food.unit = detectUnit(
            productQuantityUnit: product["product_quantity_unit"] as? String,
            servingQuantityUnit: product["serving_quantity_unit"] as? String,
            quantityUnit:        product["quantity_unit"] as? String,
            categoriesTags:      product["categories_tags"] as? [String]
        )
        return food
    }

    /// Liquid vs solid detection. v2 addition (not in v0) — kept in its own
    /// function so the v0 parser stays untouched.
    static func detectUnit(
        productQuantityUnit: String?,
        servingQuantityUnit: String?,
        quantityUnit: String?,
        categoriesTags: [String]?
    ) -> String {
        let candidates = [productQuantityUnit, servingQuantityUnit, quantityUnit]
            .compactMap { $0?.lowercased().trimmingCharacters(in: .whitespaces) }
        for c in candidates {
            if ["ml", "cl", "l"].contains(c) { return "ml" }
            if ["g", "kg", "mg"].contains(c) { return "g" }
        }
        let liquidCategories: Set<String> = [
            "en:beverages", "en:drinks", "en:waters", "en:milks",
            "en:juices", "en:sodas", "en:beers", "en:wines",
            "en:spirits", "en:dairy-drinks", "en:plant-based-milks",
            "en:syrups", "en:sauces",
        ]
        let tags = Set((categoriesTags ?? []).map { $0.lowercased() })
        if !tags.intersection(liquidCategories).isEmpty { return "ml" }
        return "g"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
