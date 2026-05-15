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

    // Audit H14 — bounded ranges so a typo of "99999" min or "5000" km
    // doesn't silently save garbage. 1440 min = one full day; 300 km
    // is well above the longest single sportive cyclists log here.
    private static let durationRangeMin: ClosedRange<Double> = 1...1440
    private static let distanceRangeKm:  ClosedRange<Double> = 0...300

    private var durationValidation: FieldValidation {
        FieldValidation(
            text: durationText,
            range: Self.durationRangeMin,
            errorMessage: "Duration must be 1–1440 minutes"
        )
    }
    private var distanceValidation: FieldValidation {
        FieldValidation(
            text: distanceText,
            range: Self.distanceRangeKm,
            errorMessage: "Distance must be 0–300 km"
        )
    }

    private var parsedDurationMin: Int? {
        durationValidation.parsedInRange.map { Int($0) }
    }

    private var parsedDistanceKm: Double? {
        distanceValidation.parsedInRange
    }

    private var canSave: Bool {
        parsedDurationMin != nil && distanceValidation.error == nil
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
                    if let err = durationValidation.error {
                        Text(err).font(.caption).foregroundStyle(.red)
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
                    if let err = distanceValidation.error {
                        Text(err).font(.caption).foregroundStyle(.red)
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
                        .disabled(!canSave)
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
