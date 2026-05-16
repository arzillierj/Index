import SwiftUI

/// Edit sheet for the Anthropic API key. The key is stored in
/// Keychain (`ClaudeService.setAPIKey`) and never displayed back
/// — SecureField starts empty in both the "Set" and "Configured"
/// states. To change a configured key the user re-pastes; the
/// Keychain entry is overwritten on save.
///
/// `onError` is the SettingsView non-blocking banner — surfaces
/// a "key save failed" message if `SecItemAdd` returns
/// `errSecDuplicateItem` or similar (rare in practice but
/// audited as a write path).
struct AIAPIKeyEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ClaudeService.self) private var claudeService

    @State private var draftKey: String = ""
    @State private var showRemoveConfirm = false
    @FocusState private var focused: Bool

    private var canSave: Bool {
        !draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $draftKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                } header: {
                    Text("Anthropic API key")
                } footer: {
                    // Two-line guidance: where to get a key, and
                    // the storage contract. The key never leaves
                    // the device; Index does not see it server-side.
                    Text(claudeService.hasAPIKey
                         ? "Paste a new key to replace the existing one. Stored only on this device."
                         : "Paste your key from console.anthropic.com. Stored only on this device.")
                }

                if claudeService.hasAPIKey {
                    Section {
                        Button(role: .destructive) {
                            showRemoveConfirm = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Remove key")
                            }
                        }
                    }
                }
            }
            .navigationTitle("API key")
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
                Task { @MainActor in focused = true }
            }
            .confirmationDialog(
                "Remove API key?",
                isPresented: $showRemoveConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    claudeService.clearAPIKey()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the key from this device. You can paste a new one anytime to re-enable AI estimates.")
            }
        }
        .tint(IndexPalette.Module.settings)
    }

    private func save() {
        do {
            try claudeService.setAPIKey(draftKey)
            dismiss()
        } catch {
            onError("Couldn't save API key. Try again.")
            dismiss()
        }
    }
}
