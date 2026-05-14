import SwiftUI
import SwiftData

/// Manual cycling log. Required: duration, intensity 1–5. Optional:
/// distance, notes. Date/time picker is required (defaults to now).
struct LogCyclingSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var durationText: String = ""
    @State private var intensity: Int = 3
    @State private var distanceText: String = ""
    @State private var notes: String = ""
    @State private var date: Date = .now
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case duration, distance, notes
    }

    private var parsedDurationMin: Int? {
        let v = Int(durationText)
        return (v.map { $0 > 0 } == true) ? v : nil
    }

    private var parsedDistanceKm: Double? {
        Double(distanceText.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Duration") {
                    HStack {
                        TextField("45", text: $durationText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .duration)
                        Text("minutes").foregroundStyle(.secondary)
                    }
                }

                Section("Intensity") {
                    Picker("Intensity", selection: $intensity) {
                        ForEach(1...5, id: \.self) { i in
                            Text("\(i)").tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(intensityHint(intensity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        TextField("Distance", text: $distanceText)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .distance)
                        Text("km").foregroundStyle(.secondary)
                    }
                    DatePicker(
                        "Date",
                        selection: $date,
                        in: ...Date.now,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                } header: {
                    Text("Optional")
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($focusedField, equals: .notes)
                }
            }
            .navigationTitle("Cycling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(parsedDurationMin == nil)
                }
            }
            .onAppear {
                Task { @MainActor in
                    focusedField = .duration
                }
            }
        }
    }

    private func intensityHint(_ i: Int) -> String {
        switch i {
        case 1: "Recovery — very easy."
        case 2: "Easy — conversation pace."
        case 3: "Moderate — comfortably hard."
        case 4: "Hard — sustained effort."
        case 5: "Very hard — near max."
        default: ""
        }
    }

    private func save() {
        guard let mins = parsedDurationMin else { return }
        let dist = parsedDistanceKm
        let session = WorkoutSession(
            date: date,
            type: .cycling,
            durationMinutes: mins,
            distanceKm: dist ?? 0,
            hasDistance: dist != nil && (dist ?? 0) > 0,
            intensity: intensity,
            hasIntensity: true,
            source: .manual,
            notes: notes
        )
        context.insert(session)
        dismiss()
    }
}
