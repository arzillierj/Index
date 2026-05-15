import SwiftUI

/// Single-field edit sheet for `Profile.proteinTargetG`. 50–300 g range.
struct ProteinTargetEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService

    @State private var draftText: String = ""
    @FocusState private var focused: Bool

    private static let range: ClosedRange<Double> = 50...300

    private var validation: FieldValidation {
        FieldValidation(
            text: draftText,
            range: Self.range,
            errorMessage: "Protein target must be 50–300 g/day"
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Protein target") {
                    HStack {
                        TextField("167", text: $draftText)
                            .keyboardType(.numberPad)
                            .focused($focused)
                        Text("g/day").foregroundStyle(.secondary)
                    }
                    if let err = validation.error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Protein target")
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
                if let g = profileService.activeProfile?.proteinTargetG {
                    draftText = "\(Int(g.rounded()))"
                }
                Task { @MainActor in focused = true }
            }
        }
        .tint(IndexAccent.green)
    }

    private func save() {
        guard let g = validation.parsedInRange else { return }
        do {
            try profileService.updateProteinTarget(g, in: context)
            dismiss()
        } catch {
            onError("Couldn't save protein target. Try again.")
            dismiss()
        }
    }
}
