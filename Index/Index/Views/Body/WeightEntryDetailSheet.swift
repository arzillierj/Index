import SwiftUI
import SwiftData

/// Edit / delete an existing WeightEntry. Same range guards as
/// LogWeightSheet (weight 20–300 kg, body fat 0–60%, lean mass 20–200 kg)
/// so a stored row can't be re-saved with an obviously bad value. Delete
/// sets `deletedFromIndex = true` and intentionally does NOT delete from
/// Apple Health (HK is a peer store; the v0 audit pattern).
///
/// Edits are held in local draft state until Save so Cancel reliably
/// rolls back — SwiftData auto-saves on @Bindable mutation, so binding
/// directly to the model would commit changes immediately and make
/// Cancel meaningless.
struct WeightEntryDetailSheet: View {
    let entry: WeightEntry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var weightText: String = ""
    @State private var bodyFatText: String = ""
    @State private var leanMassText: String = ""
    @State private var notes: String = ""
    @State private var date: Date = .now
    @State private var showDeleteConfirm = false
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
        weightValidation.parsedInRange != nil
            && bodyFatValidation.error == nil
            && leanMassValidation.error == nil
    }

    private var sourceCaption: String {
        switch entry.source {
        case .renpho:    "From RENPHO via Apple Health"
        case .healthkit: "From Apple Health"
        case .manual:    "Logged in Index"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                } header: {
                    Text("Weight")
                } footer: {
                    Text(sourceCaption)
                }

                Section("Body composition") {
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
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .notes)
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete entry")
                        }
                    }
                }
            }
            .navigationTitle("Entry")
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
            .onAppear(perform: populate)
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteEntry)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes it from Index. Apple Health is unaffected.")
            }
        }
    }

    private func populate() {
        weightText = SafeFormat.decimal(entry.weightKg)
        bodyFatText = entry.hasBodyFat ? SafeFormat.percent(entry.bodyFatPercent) : ""
        leanMassText = entry.hasLeanMass ? SafeFormat.decimal(entry.leanMassKg) : ""
        notes = entry.notes
        date = entry.date
    }

    private func save() {
        guard let weightKg = weightValidation.parsedInRange else { return }
        entry.weightKg = weightKg
        entry.date = date
        entry.notes = notes

        let bf = bodyFatValidation.parsedInRange
        entry.bodyFatPercent = bf ?? 0
        entry.hasBodyFat = bf != nil

        let lm = leanMassValidation.parsedInRange
        entry.leanMassKg = lm ?? 0
        entry.hasLeanMass = lm != nil

        dismiss()
    }

    private func deleteEntry() {
        entry.deletedFromIndex = true
        dismiss()
    }
}
