import SwiftUI

/// Single-field edit sheet for `Profile.sex`. Picker, no free input.
struct SexEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService

    @State private var draft: Sex = .male

    var body: some View {
        NavigationStack {
            Form {
                Section("Sex") {
                    Picker("Sex", selection: $draft) {
                        ForEach(Sex.allCases, id: \.self) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Sex")
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
                draft = profileService.activeProfile?.sex ?? .male
            }
        }
        .tint(IndexPalette.Module.settings)
    }

    private func save() {
        do {
            try profileService.updateSex(draft, in: context)
            dismiss()
        } catch {
            onError("Couldn't save. Try again.")
            dismiss()
        }
    }
}
