import SwiftUI
import SwiftData

/// Result sheet for a scanned barcode. Hits the local FoodProduct cache
/// first (90-day refresh window); on a miss, falls through to the OFF
/// API. On success, the user picks a quantity (slider 10–800 step 5)
/// and saves a NutritionEntry; the FoodProduct cache is upserted in the
/// same step.
///
/// Port of the v0 ScannedProductSheet — slider UX + per-100 macros + scaled
/// macros, keeping v2's loading/error phases and FoodProduct cache.
struct BarcodeResultSheet: View {
    let barcode: String
    let onFallbackToManual: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allProducts: [FoodProduct]

    @State private var phase: Phase = .loading
    @State private var food: ScannedFood? = nil
    @State private var grams: Double = 100
    @State private var mealType: MealType = .snack
    @State private var date: Date = .now
    @State private var dataSource: DataSource = .api
    /// Source of truth for the unit toggle. Initialised from
    /// `food.unit` (which carries the OFF detection result) on load,
    /// then user-controllable via the segmented picker. Drives
    /// `unit` everywhere it's displayed; macros recompute via
    /// `food.macros(forGrams:)` against the current `grams` value
    /// regardless of toggle state (per-100 base unit is fixed by
    /// the OFF data; the toggle only relabels the quantity).
    @State private var selectedUnit: String = "g"

    enum Phase {
        case loading
        case ready
        case notFound
        case networkError
    }

    enum DataSource {
        case api, cache
        var label: String {
            switch self {
            case .api:   "From Open Food Facts"
            case .cache: "Cached"
            }
        }
    }

    private var unit: String { selectedUnit }

    private var macros: (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        food?.macros(forGrams: grams) ?? (0, 0, 0, 0)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Scanned product")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if case .ready = phase {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save", action: save)
                        }
                    }
                }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:      loadingView
        case .ready:        readyForm
        case .notFound:     errorView("Couldn't find this product. Enter it manually?")
        case .networkError: errorView("No internet connection. Try again or enter manually.")
        }
    }

    // MARK: - Phases

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Looking up product…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "questionmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(barcode)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Enter manually") {
                onFallbackToManual(barcode)
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var readyForm: some View {
        if let food {
            Form {
                Section { productHeader(food) }

                Section("Quantity") {
                    quantityRow
                    shortcutChips
                }

                Section("Macros for \(Int(grams)) \(unit)") {
                    macroRow("Calories", value: macros.kcal,    suffix: "kcal")
                    macroRow("Protein",  value: macros.protein, suffix: "g")
                    macroRow("Carbs",    value: macros.carbs,   suffix: "g")
                    macroRow("Fat",      value: macros.fat,     suffix: "g")
                }

                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
        }
    }

    // MARK: - Ready-form pieces

    private func productHeader(_ food: ScannedFood) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(food.name.isEmpty ? "Unknown product" : food.name)
                .font(.headline)
            if !food.brand.isEmpty {
                Text(food.brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(dataSource.label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(barcode)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            HStack(alignment: .top, spacing: 8) {
                per100Tile("\(SafeFormat.int(food.kcalPer100g)) kcal")
                per100Tile(String(format: "%.1fg Protein", food.proteinPer100g))
                per100Tile(String(format: "%.1fg Carbs",   food.carbsPer100g))
                per100Tile(String(format: "%.1fg Fat",     food.fatPer100g))
            }
            .padding(.top, 6)

            Text("per 100\(unit)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline tile: full word labels ("Protein", "Carbs", "Fat") next
    /// to the value in a single Text so wrapping is per-tile when the
    /// row is too narrow. lineLimit unset — never truncate.
    private func per100Tile(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var quantityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(Int(grams))")
                    .font(.system(size: 36, weight: .semibold, design: .monospaced))
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Unit", selection: $selectedUnit) {
                    Text("g").tag("g")
                    Text("ml").tag("ml")
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
            }
            Slider(value: $grams, in: 10...800, step: 5)
        }
        .padding(.vertical, 4)
    }

    private var shortcutChips: some View {
        let values: [Int] = unit == "g"
            ? [30, 50, 100, 150, 200]
            : [100, 200, 250, 330, 500]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { v in
                    Button {
                        grams = Double(v)
                    } label: {
                        Text("\(v) \(unit)")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(IndexPalette.Surface.divider))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func macroRow(_ label: String, value: Double, suffix: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(SafeFormat.int(value)) \(suffix)")
                .font(.body.monospacedDigit())
        }
    }

    // MARK: - Load + save

    private func load() async {
        let cached = allProducts.first { $0.barcode == barcode }
        let cacheCutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now) ?? .distantPast

        if let cached, cached.lastUsed >= cacheCutoff {
            print("BarcodeResultSheet: cache hit for \(barcode).")
            cached.lastUsed = .now
            let resolvedUnit = cached.unit.isEmpty ? "g" : cached.unit
            food = ScannedFood(
                barcode: cached.barcode,
                name: cached.name,
                brand: cached.brand,
                kcalPer100g: cached.kcalPer100g,
                proteinPer100g: cached.proteinPer100g,
                carbsPer100g: cached.carbsPer100g,
                fatPer100g: cached.fatPer100g,
                unit: resolvedUnit
            )
            selectedUnit = resolvedUnit
            dataSource = .cache
            phase = .ready
            return
        }

        print("BarcodeResultSheet: fetching OFF for \(barcode) (cache miss).")
        do {
            let fetched = try await OpenFoodFactsService.fetch(barcode: barcode)
            print("DEBUG fetched: name=\(fetched.name) kcal=\(fetched.kcalPer100g) protein=\(fetched.proteinPer100g) carbs=\(fetched.carbsPer100g) fat=\(fetched.fatPer100g) unit=\(fetched.unit)")
            food = fetched
            selectedUnit = fetched.unit
            dataSource = .api
            phase = .ready
            upsertCacheFromFetch(fetched, existing: cached)
        } catch OFFError.notFound {
            phase = .notFound
        } catch {
            phase = .networkError
        }
    }

    /// Cache the fresh OFF data immediately so the next scan of this
    /// barcode is a cache hit even if the user cancels without saving.
    /// useCount only increments on Save.
    private func upsertCacheFromFetch(_ f: ScannedFood, existing: FoodProduct?) {
        let target: FoodProduct
        if let existing {
            target = existing
        } else {
            target = FoodProduct(barcode: f.barcode)
            context.insert(target)
        }
        target.name           = f.name
        target.brand          = f.brand
        target.kcalPer100g    = f.kcalPer100g
        target.proteinPer100g = f.proteinPer100g
        target.carbsPer100g   = f.carbsPer100g
        target.fatPer100g     = f.fatPer100g
        target.unit           = f.unit
        target.lastUsed       = .now
    }

    private func save() {
        guard let food else { return }
        let m = food.macros(forGrams: grams)

        // FetchDescriptor (not @Query) — applyProduct may have just
        // inserted a row in this same frame; @Query hasn't necessarily
        // observed it yet.
        //
        // Audit H15 — explicit do/catch around the dedup fetch. The
        // previous `try?` swallowed errors silently, which would have
        // routed a real fetch failure into the "no existing → insert
        // new" branch and silently double-inserted a FoodProduct row
        // with the same barcode. On failure here we abort the save
        // without dismissing so the user can retry; the local
        // NutritionEntry insert below also doesn't run, so nothing
        // is half-committed.
        let barcodeKey = barcode
        let descriptor = FetchDescriptor<FoodProduct>(
            predicate: #Predicate { $0.barcode == barcodeKey }
        )
        let existing: FoodProduct?
        do {
            existing = try context.fetch(descriptor).first
        } catch {
            print("[BarcodeResultSheet] dedup fetch failed: \(error) — aborting save")
            return
        }

        if let existing {
            existing.name           = food.name
            existing.brand          = food.brand
            existing.kcalPer100g    = food.kcalPer100g
            existing.proteinPer100g = food.proteinPer100g
            existing.carbsPer100g   = food.carbsPer100g
            existing.fatPer100g     = food.fatPer100g
            existing.unit           = food.unit
            existing.lastUsed       = .now
            existing.useCount      += 1
        } else {
            let product = FoodProduct(
                barcode: food.barcode,
                name: food.name,
                brand: food.brand,
                kcalPer100g: food.kcalPer100g,
                proteinPer100g: food.proteinPer100g,
                carbsPer100g: food.carbsPer100g,
                fatPer100g: food.fatPer100g,
                lastUsed: .now,
                useCount: 1,
                unit: food.unit
            )
            context.insert(product)
        }

        let entry = NutritionEntry(
            date: date,
            label: food.name.isEmpty ? "Barcode \(barcode)" : food.name,
            kcal: m.kcal,
            protein: m.protein,
            carbs: m.carbs,
            fat: m.fat,
            mealType: mealType,
            source: .barcode
        )
        context.insert(entry)
        print("DEBUG sheet save: kcal=\(m.kcal) protein=\(m.protein) carbs=\(m.carbs) fat=\(m.fat) grams=\(grams)")
        dismiss()
    }
}
