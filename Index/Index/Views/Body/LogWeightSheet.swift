import SwiftUI
import SwiftData

/// Manual weight entry with input guard rails. Weight is required and must
/// fall in 20–300 kg. Body fat % (0–60) and lean mass (20–200 kg) are
/// optional but, when entered, must be in range — Save stays disabled
/// otherwise and an inline error renders beneath the field.
///
/// The 2026-05-14 corruption incident (weight ~5×10³⁸ kg) was traced to
/// either upstream HK noise or accidental keystroke runaway; the
/// validation here is the floor that keeps obviously-bad values out of
/// the SwiftData store.
struct LogWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var hkService

    @Query(
        filter: #Predicate<WeightEntry> { !$0.deletedFromIndex },
        sort: \WeightEntry.date,
        order: .reverse
    )
    private var existingEntries: [WeightEntry]

    @State private var weightText: String = ""
    @State private var bodyFatText: String = ""
    @State private var leanMassText: String = ""
    @State private var notes: String = ""
    @State private var date: Date = .now
    @State private var hkErrorMessage: String? = nil
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight, bodyFat, leanMass, notes
    }

    private static let weightRangeKg: ClosedRange<Double> = 20...300
    private static let bodyFatRangePct: ClosedRange<Double> = 0...60
    private static let leanMassRangeKg: ClosedRange<Double> = 20...200

    private var weightValidation: FieldValidation {
        FieldValidation(
            text: weightText,
            range: Self.weightRangeKg,
            errorMessage: "Weight must be between 20 and 300 kg"
        )
    }

    private var bodyFatValidation: FieldValidation {
        FieldValidation(
            text: bodyFatText,
            range: Self.bodyFatRangePct,
            errorMessage: "Body fat must be between 0 and 60%"
        )
    }

    private var leanMassValidation: FieldValidation {
        FieldValidation(
            text: leanMassText,
            range: Self.leanMassRangeKg,
            errorMessage: "Lean mass must be between 20 and 200 kg"
        )
    }

    private var canSave: Bool {
        // Weight is required AND in range. Optional fields, when entered,
        // must also be in range.
        weightValidation.parsedInRange != nil
            && bodyFatValidation.error == nil
            && leanMassValidation.error == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let msg = hkErrorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                Text("Saved locally — Apple Health write failed.")
                                    .font(.subheadline.weight(.medium))
                            }
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Dismiss") { dismiss() }
                                .font(.caption.weight(.semibold))
                                .padding(.top, 2)
                        }
                    }
                }
                Section("Weight") {
                    HStack {
                        TextField("75.0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .weight)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    if let err = weightValidation.error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section {
                    HStack {
                        TextField("Body fat", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .bodyFat)
                        Text("%").foregroundStyle(.secondary)
                    }
                    if let err = bodyFatValidation.error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        TextField("Lean mass", text: $leanMassText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .leanMass)
                        Text("kg").foregroundStyle(.secondary)
                    }
                    if let err = leanMassValidation.error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Body composition")
                } footer: {
                    Text("Optional. Leave blank if your scale didn't measure these.")
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle("Log weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave || isSaving)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        if let last = existingEntries.first, weightText.isEmpty {
            weightText = SafeFormat.decimal(last.weightKg)
        }
        Task { @MainActor in
            focusedField = .weight
        }
    }

    private func save() {
        guard let weightKg = weightValidation.parsedInRange else { return }
        let bodyFat = bodyFatValidation.parsedInRange
        let leanMass = leanMassValidation.parsedInRange

        // Local entry is durable regardless of HK outcome (DQ3 — Apple
        // Health is a peer, not master). Insert + save before attempting
        // the HK mirror so a HK failure can never strand the local row.
        let entry = WeightEntry(
            date: date,
            weightKg: weightKg,
            bodyFatPercent: bodyFat ?? 0,
            hasBodyFat: bodyFat != nil,
            leanMassKg: leanMass ?? 0,
            hasLeanMass: leanMass != nil,
            notes: notes,
            source: .manual,
            deletedFromIndex: false
        )
        context.insert(entry)
        try? context.save()

        // HK mirror — async + throws (audit H4). Success → dismiss.
        // Failure → keep the sheet open and surface a banner so the
        // user knows other Health-reading apps won't see this value
        // (and they can decide to retry from the home screen or
        // ignore).
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await hkService.saveWeight(kg: weightKg, date: date)
                dismiss()
            } catch {
                hkErrorMessage = error.localizedDescription
            }
        }
    }
}

/// Three-state validation for a single numeric form field.
///
///   parsed         — Double if the text parses, regardless of range.
///   parsedInRange  — Double if the text parses AND falls in `range`.
///                    Empty input ⇒ nil (treated as "field not provided").
///   error          — non-nil when the user typed something out of range
///                    or unparseable. Empty input ⇒ no error.
struct FieldValidation {
    let parsed: Double?
    let parsedInRange: Double?
    let error: String?

    init(text: String, range: ClosedRange<Double>, errorMessage: String) {
        let trimmed = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        if trimmed.isEmpty {
            self.parsed = nil
            self.parsedInRange = nil
            self.error = nil
            return
        }
        guard let v = Double(trimmed), v.isFinite else {
            self.parsed = nil
            self.parsedInRange = nil
            self.error = errorMessage
            return
        }
        self.parsed = v
        if range.contains(v) {
            self.parsedInRange = v
            self.error = nil
        } else {
            self.parsedInRange = nil
            self.error = errorMessage
        }
    }
}
