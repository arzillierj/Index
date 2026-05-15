import SwiftUI

/// Single-field edit sheet for `Profile.age`. 13–120 range mirrors the
/// onboarding Stepper's range (audit H13 numeric guard discipline —
/// Settings edits are validated the same way as onboarding entries).
struct AgeEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService

    @State private var draft: Int = 30

    private static let range: ClosedRange<Int> = 13...120

    var body: some View {
        NavigationStack {
            Form {
                Section("Age") {
                    Stepper(value: $draft, in: Self.range) {
                        Text("\(draft)")
                            .monospacedDigit()
                    }
                }
            }
            .navigationTitle("Age")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear {
                draft = profileService.activeProfile?.age ?? 30
            }
        }
        .tint(IndexPalette.Module.settings)
    }

    private func save() {
        do {
            try profileService.updateAge(draft, in: context)
            dismiss()
        } catch {
            onError("Couldn't save age. Try again.")
            dismiss()
        }
    }
}
