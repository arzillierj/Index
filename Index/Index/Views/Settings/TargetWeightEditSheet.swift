import SwiftUI

/// Single-field edit sheet for `Profile.targetWeightKg` + the
/// `hasTargetWeight` companion. 30–300 kg range mirrors onboarding's
/// audit H13 guard. The "Set a target weight" toggle gates whether the
/// numeric field is visible, mirroring the onboarding pattern.
struct TargetWeightEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService

    @State private var hasTarget: Bool = false
    @State private var draftText: String = ""
    @FocusState private var focused: Bool

    private static let range: ClosedRange<Double> = 30...300

    private var validation: FieldValidation {
        FieldValidation(
            text: draftText,
            range: Self.range,
            errorMessage: "Target weight must be 30–300 kg"
        )
    }

    private var canSave: Bool {
        !hasTarget || validation.parsedInRange != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Set a target weight", isOn: $hasTarget.animation())
                        .tint(IndexAccent.green)
                }
                if hasTarget {
                    Section("Target weight") {
                        HStack {
                            TextField("75", text: $draftText)
                                .keyboardType(.decimalPad)
                                .focused($focused)
                            Text("kg").foregroundStyle(.secondary)
                        }
                        if let err = validation.error {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Target weight")
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
                if let p = profileService.activeProfile {
                    hasTarget = p.hasTargetWeight
                    if p.hasTargetWeight, p.targetWeightKg > 0 {
                        draftText = SafeFormat.decimal(p.targetWeightKg)
                    }
                }
                if hasTarget {
                    Task { @MainActor in focused = true }
                }
            }
        }
        .tint(IndexAccent.green)
    }

    private func save() {
        let kg = hasTarget ? (validation.parsedInRange ?? 0) : 0
        do {
            try profileService.updateTargetWeight(kg, hasTarget: hasTarget, in: context)
            dismiss()
        } catch {
            onError("Couldn't save target weight. Try again.")
            dismiss()
        }
    }
}
