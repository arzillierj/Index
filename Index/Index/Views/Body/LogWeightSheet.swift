import SwiftUI
import SwiftData

/// Manual weight entry. Body fat % and lean mass are optional (leave blank
/// to mark them as not provided). Save inserts a WeightEntry with
/// source: .manual and mirrors the weight value to Apple Health.
struct LogWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

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
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight, bodyFat, leanMass, notes
    }

    private var parsedWeightKg: Double? {
        let v = Double(weightText.replacingOccurrences(of: ",", with: "."))
        return (v.map { $0 > 0 } == true) ? v : nil
    }

    private var parsedBodyFat: Double? {
        Double(bodyFatText.replacingOccurrences(of: ",", with: "."))
    }

    private var parsedLeanMass: Double? {
        Double(leanMassText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
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
                }

                Section {
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
                        .disabled(parsedWeightKg == nil)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        // Default to the most recent weight so the user sees a sensible
        // starting value instead of an empty field.
        if let last = existingEntries.first, weightText.isEmpty {
            weightText = formatKg(last.weightKg)
        }
        // Race-free focus: hop through MainActor so SwiftUI has installed
        // the TextField before the focus assignment lands.
        Task { @MainActor in
            focusedField = .weight
        }
    }

    private func save() {
        guard let weightKg = parsedWeightKg else { return }
        let bodyFat = parsedBodyFat
        let leanMass = parsedLeanMass

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
        // Mirror weight only to HealthKit. v2 doesn't write body fat / lean
        // mass back — those flow inbound from the scale (RENPHO writes
        // them; we just read).
        HealthKitService.saveWeight(kg: weightKg, date: date)
        dismiss()
    }

    private func formatKg(_ kg: Double) -> String {
        kg == floor(kg) ? "\(Int(kg))" : String(format: "%.1f", kg)
    }
}
