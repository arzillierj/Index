import SwiftUI
import SwiftData

/// Parameterized log sheet for the four non-cycling, non-strength activities
/// — running, swimming, squash, and the catch-all "other". The preset
/// controls which optional fields show and whether a sub-type picker is
/// surfaced (Other only).
///
/// Sub-types inside "Other" (Hiking / Walking / Yoga / Other) map to
/// WorkoutType.other and prefix the notes field with the chosen label.
/// DECISION: storing the sub-type in notes avoids a third schema bump in
/// Phase 5; the takeover doc keeps WorkoutType at six cases, and the feed
/// shows .other → "Other" for all of them, with the sub-label visible in
/// the row's notes / detail view.
struct LogOtherWorkoutSheet: View {
    let preset: WorkoutType

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var subType: String = "Other"
    @State private var durationText: String = ""
    @State private var intensity: Int = 3
    @State private var distanceText: String = ""
    @State private var notes: String = ""
    @State private var date: Date = .now
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case duration, distance, notes
    }

    private static let subTypes = ["Hiking", "Walking", "Yoga", "Other"]

    // Audit H14 — bounded ranges (mirrors LogCyclingSheet). Distance
    // applies only to .running / .swimming presets per `showsDistance`.
    private static let durationRangeMin: ClosedRange<Double> = 1...1440
    private static let distanceRangeKm:  ClosedRange<Double> = 0...300

    private var showsDistance: Bool {
        preset == .running || preset == .swimming
    }

    private var showsSubTypePicker: Bool {
        preset == .other
    }

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
        parsedDurationMin != nil
            && (!showsDistance || distanceValidation.error == nil)
    }

    private var title: String {
        showsSubTypePicker ? "Other workout" : preset.label
    }

    var body: some View {
        NavigationStack {
            Form {
                if showsSubTypePicker {
                    Section("Type") {
                        Picker("Type", selection: $subType) {
                            ForEach(Self.subTypes, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

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
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(intensityHint(intensity))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    if showsDistance {
                        HStack {
                            TextField("Distance", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .distance)
                            Text("km").foregroundStyle(.secondary)
                        }
                        if let err = distanceValidation.error {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
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
            .navigationTitle(title)
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

        // Prefix the notes with the sub-type label when it's a meaningful
        // distinction (anything other than "Other"). Keeps the feed row's
        // notes display informative without a schema field.
        let prefix = (showsSubTypePicker && subType != "Other") ? "\(subType) · " : ""
        let finalNotes = prefix + notes

        let session = WorkoutSession(
            date: date,
            type: preset,
            durationMinutes: mins,
            distanceKm: dist ?? 0,
            hasDistance: showsDistance && dist != nil && (dist ?? 0) > 0,
            intensity: intensity,
            hasIntensity: true,
            source: .manual,
            notes: finalNotes
        )
        context.insert(session)
        dismiss()
    }
}
