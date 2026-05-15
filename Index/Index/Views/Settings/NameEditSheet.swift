import SwiftUI

/// Single-field edit sheet for `Profile.name`. Save disabled until the
/// trimmed value is non-empty; on save error, dismisses + bubbles the
/// message to SettingsView's banner via `onError`.
struct NameEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    private var isValid: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Your name", text: $draft)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .onAppear {
                draft = profileService.activeProfile?.name ?? ""
                Task { @MainActor in focused = true }
            }
        }
        .tint(IndexAccent.green)
    }

    private func save() {
        do {
            try profileService.updateName(draft, in: context)
            dismiss()
        } catch {
            onError("Couldn't save name. Try again.")
            dismiss()
        }
    }
}
