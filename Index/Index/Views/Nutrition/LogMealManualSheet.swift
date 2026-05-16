import SwiftUI
import SwiftData

/// Manual meal entry with FieldValidation guard rails — kcal is required
/// and must fall in 0–5000; protein / carbs / fat are optional but, when
/// entered, must be in 0–500 g. Mirrors LogWeightSheet's pattern.
///
/// When `editing` is non-nil the form pre-fills from that entry and
/// updates it in place on Save; otherwise a new NutritionEntry is
/// inserted with source = .manual.
struct LogMealManualSheet: View {
    let editing: NutritionEntry?
    /// When `editing` is nil, pre-fills the label field — used by the
    /// barcode flow when OFF lookup fails and the user falls back to
    /// manual entry, AND by the frequent-foods chip row on Nutrition main
    /// (along with the four macro pre-fills below). Ignored in edit mode
    /// (the entry's own label wins).
    var prefilledLabel: String? = nil
    /// When non-nil and `editing` is nil, pre-fill the macro fields. Used
    /// by the frequent-foods chip flow so the user can save the same
    /// macros as the most recent entry of that label with one tap. Each
    /// is independent — partial pre-fills (e.g., only kcal known) are
    /// allowed.
    var prefilledKcal:    Double? = nil
    var prefilledProtein: Double? = nil
    var prefilledCarbs:   Double? = nil
    var prefilledFat:     Double? = nil
    /// Pre-selects the meal-type picker (Breakfast / Lunch /
    /// Dinner / Snack). Used by the food-history re-log path so
    /// a re-logged dinner stays a dinner. Ignored when `editing`
    /// is non-nil (the entry's own type wins). Other prefill
    /// paths (AI, barcode, frequent-foods chips) leave this nil
    /// and the sheet defaults to `.snack`.
    var prefilledMealType: MealType? = nil
    /// Optional hint when the pre-fill came from the AI estimator
    /// rather than a barcode lookup or frequent-foods chip. Drives
    /// a small "AI estimate — check the numbers" caption at the
    /// top of the form. `confidence` is the model's self-reported
    /// confidence string ("low"/"medium"/"high"); "low" makes the
    /// caption warning-tinted so the user knows to scrutinise.
    var aiPrefillHint: AIPrefillHint? = nil

    struct AIPrefillHint: Equatable {
        let confidence: String
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var label: String = ""
    @State private var kcalText: String = ""
    @State private var proteinText: String = ""
    @State private var carbsText: String = ""
    @State private var fatText: String = ""
    @State private var mealType: MealType = .snack
    @State private var date: Date = .now
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case label, kcal, protein, carbs, fat
    }

    private static let kcalRange:  ClosedRange<Double> = 0...5000
    private static let macroRange: ClosedRange<Double> = 0...500

    private var labelValid: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var kcalValidation: FieldValidation {
        FieldValidation(
            text: kcalText,
            range: Self.kcalRange,
            errorMessage: "Calories must be between 0 and 5000"
        )
    }
    private var proteinValidation: FieldValidation {
        FieldValidation(
            text: proteinText,
            range: Self.macroRange,
            errorMessage: "Protein must be between 0 and 500 g"
        )
    }
    private var carbsValidation: FieldValidation {
        FieldValidation(
            text: carbsText,
            range: Self.macroRange,
            errorMessage: "Carbs must be between 0 and 500 g"
        )
    }
    private var fatValidation: FieldValidation {
        FieldValidation(
            text: fatText,
            range: Self.macroRange,
            errorMessage: "Fat must be between 0 and 500 g"
        )
    }

    private var canSave: Bool {
        labelValid
            && kcalValidation.parsedInRange != nil
            && proteinValidation.error == nil
            && carbsValidation.error == nil
            && fatValidation.error == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let hint = aiPrefillHint {
                    Section {
                        aiCaption(hint: hint)
                    }
                }
                Section("Food") {
                    TextField("Label (e.g. Oatmeal with banana)", text: $label)
                        .focused($focusedField, equals: .label)
                }

                Section("Macros") {
                    HStack {
                        TextField("0", text: $kcalText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .kcal)
                        Text("kcal").foregroundStyle(.secondary)
                    }
                    if let e = kcalValidation.error {
                        Text(e).font(.caption).foregroundStyle(IndexPalette.Semantic.error)
                    }
                    HStack {
                        TextField("Protein", text: $proteinText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .protein)
                        Text("g").foregroundStyle(.secondary)
                    }
                    if let e = proteinValidation.error {
                        Text(e).font(.caption).foregroundStyle(IndexPalette.Semantic.error)
                    }
                    HStack {
                        TextField("Carbs", text: $carbsText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .carbs)
                        Text("g").foregroundStyle(.secondary)
                    }
                    if let e = carbsValidation.error {
                        Text(e).font(.caption).foregroundStyle(IndexPalette.Semantic.error)
                    }
                    HStack {
                        TextField("Fat", text: $fatText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .fat)
                        Text("g").foregroundStyle(.secondary)
                    }
                    if let e = fatValidation.error {
                        Text(e).font(.caption).foregroundStyle(IndexPalette.Semantic.error)
                    }
                }

                Section {
                    Picker("Meal", selection: $mealType) {
                        ForEach(MealType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }
            .navigationTitle(editing == nil ? "Log meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    /// "AI estimate — check the numbers before saving." Warning-tinted
    /// for low-confidence results so the user double-checks.
    @ViewBuilder
    private func aiCaption(hint: AIPrefillHint) -> some View {
        let isLow = hint.confidence.lowercased() == "low"
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isLow ? "exclamationmark.triangle.fill" : "sparkle")
                .foregroundStyle(isLow
                                 ? IndexPalette.Semantic.warning
                                 : IndexPalette.Module.nutrition)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI estimate")
                    .font(.subheadline.weight(.semibold))
                Text(isLow
                     ? "Low confidence — double-check the numbers before saving."
                     : "Check the numbers before saving.")
                    .font(.caption)
                    .foregroundStyle(IndexPalette.Text.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func prefill() {
        if let entry = editing {
            label = entry.label
            kcalText = SafeFormat.int(entry.kcal)
            proteinText = entry.protein > 0 ? SafeFormat.int(entry.protein) : ""
            carbsText = entry.carbs > 0 ? SafeFormat.int(entry.carbs) : ""
            fatText = entry.fat > 0 ? SafeFormat.int(entry.fat) : ""
            mealType = entry.mealType
            date = entry.date
        } else {
            if let prefilledLabel, label.isEmpty {
                label = prefilledLabel
            }
            if let kcal = prefilledKcal, kcalText.isEmpty {
                kcalText = SafeFormat.int(kcal)
            }
            if let protein = prefilledProtein, proteinText.isEmpty, protein > 0 {
                proteinText = SafeFormat.int(protein)
            }
            if let carbs = prefilledCarbs, carbsText.isEmpty, carbs > 0 {
                carbsText = SafeFormat.int(carbs)
            }
            if let fat = prefilledFat, fatText.isEmpty, fat > 0 {
                fatText = SafeFormat.int(fat)
            }
            if let prefilledMealType {
                mealType = prefilledMealType
            }
        }
        Task { @MainActor in
            focusedField = editing == nil ? .label : nil
        }
    }

    private func save() {
        guard let kcal = kcalValidation.parsedInRange else { return }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        let protein = proteinValidation.parsedInRange ?? 0
        let carbs   = carbsValidation.parsedInRange   ?? 0
        let fat     = fatValidation.parsedInRange     ?? 0

        if let entry = editing {
            entry.label = trimmed
            entry.kcal = kcal
            entry.protein = protein
            entry.carbs = carbs
            entry.fat = fat
            entry.mealType = mealType
            entry.date = date
        } else {
            let entry = NutritionEntry(
                date: date,
                label: trimmed,
                kcal: kcal,
                protein: protein,
                carbs: carbs,
                fat: fat,
                mealType: mealType,
                source: .manual
            )
            context.insert(entry)
        }
        dismiss()
    }
}
