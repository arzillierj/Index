import SwiftUI

/// Single-field edit sheet for `Profile.goal` — the user-facing
/// "direction" label (Cutting / Maintaining / Bulking) maps to the
/// model's `Goal.lose / .maintain / .gain`. The model labels stay as
/// "Lose weight" / "Maintain" / "Gain weight" because that vocabulary
/// is also used in onboarding; settings introduces the cutting/bulking
/// terminology without changing the underlying enum.
struct DirectionEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService

    @State private var draft: Goal = .maintain

    var body: some View {
        NavigationStack {
            Form {
                Section("Direction") {
                    Picker("Direction", selection: $draft) {
                        Text("Cutting").tag(Goal.lose)
                        Text("Maintaining").tag(Goal.maintain)
                        Text("Bulking").tag(Goal.gain)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Direction")
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
                draft = profileService.activeProfile?.goal ?? .maintain
            }
        }
        .tint(IndexPalette.Module.settings)
    }

    private func save() {
        do {
            try profileService.updateGoal(draft, in: context)
            dismiss()
        } catch {
            onError("Couldn't save direction. Try again.")
            dismiss()
        }
    }
}
