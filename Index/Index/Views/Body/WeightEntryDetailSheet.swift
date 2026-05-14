import SwiftUI
import SwiftData

/// Edit / delete an existing WeightEntry. Delete sets
/// `deletedFromIndex = true` and intentionally does NOT delete from Apple
/// Health (HK is treated as a peer store; the v0 audit pattern).
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

    private var parsedWeightKg: Double? {
        let v = Double(weightText.replacingOccurrences(of: ",", with: "."))
        return (v.map { $0 > 0 } == true) ? v : nil
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
                    HStack {
                        TextField("Lean mass", text: $leanMassText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .leanMass)
                        Text("kg").foregroundStyle(.secondary)
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
                        .disabled(parsedWeightKg == nil)
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
        weightText = formatKg(entry.weightKg)
        bodyFatText = entry.hasBodyFat ? String(format: "%.1f", entry.bodyFatPercent) : ""
        leanMassText = entry.hasLeanMass ? formatKg(entry.leanMassKg) : ""
        notes = entry.notes
        date = entry.date
    }

    private func save() {
        guard let weightKg = parsedWeightKg else { return }
        entry.weightKg = weightKg
        entry.date = date
        entry.notes = notes

        let bf = Double(bodyFatText.replacingOccurrences(of: ",", with: "."))
        entry.bodyFatPercent = bf ?? 0
        entry.hasBodyFat = bf != nil

        let lm = Double(leanMassText.replacingOccurrences(of: ",", with: "."))
        entry.leanMassKg = lm ?? 0
        entry.hasLeanMass = lm != nil

        dismiss()
    }

    private func deleteEntry() {
        // Soft-delete only. The row remains in SwiftData so HK
        // dedup-on-re-import predicates still find it (the v0 tombstone
        // contract). Apple Health is intentionally untouched.
        entry.deletedFromIndex = true
        dismiss()
    }

    private func formatKg(_ kg: Double) -> String {
        kg == floor(kg) ? "\(Int(kg))" : String(format: "%.1f", kg)
    }
}
