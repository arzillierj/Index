import SwiftUI

/// Single-field edit sheet for `Profile.heightCm`. 100–250 cm range
/// mirrors onboarding (audit H13). FieldValidation pattern keeps the
/// save button disabled + surfaces an inline error when the user
/// types out of range.
struct HeightEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService

    @State private var draftText: String = ""
    @FocusState private var focused: Bool

    private static let range: ClosedRange<Double> = 100...250

    private var validation: FieldValidation {
        FieldValidation(
            text: draftText,
            range: Self.range,
            errorMessage: "Height must be 100–250 cm"
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Height") {
                    HStack {
                        TextField("175", text: $draftText)
                            .keyboardType(.numberPad)
                            .focused($focused)
                        Text("cm").foregroundStyle(.secondary)
                    }
                    if let err = validation.error {
                        Text(err).font(.caption).foregroundStyle(IndexPalette.Semantic.error)
                    }
                }
            }
            .navigationTitle("Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(validation.parsedInRange == nil)
                }
            }
            .onAppear {
                if let h = profileService.activeProfile?.heightCm {
                    draftText = "\(Int(h.rounded()))"
                }
                Task { @MainActor in focused = true }
            }
        }
        .tint(IndexPalette.Module.settings)
    }

    private func save() {
        guard let cm = validation.parsedInRange else { return }
        do {
            try profileService.updateHeight(cm, in: context)
            dismiss()
        } catch {
            onError("Couldn't save height. Try again.")
            dismiss()
        }
    }
}
