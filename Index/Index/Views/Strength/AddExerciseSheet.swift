import SwiftUI
import SwiftData

/// Picker over the 10-exercise starter catalog. Rows already in the user's
/// library show a checkmark and are disabled so a tap on an unrelated row
/// is unambiguous.
struct AddExerciseSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \UserExercise.displayOrder) private var existing: [UserExercise]

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCatalog.starter) { def in
                    let isAdded = existing.contains { $0.id == def.id }
                    Button {
                        add(def)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(def.name).foregroundStyle(.primary)
                                Text(def.kind.caption)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isAdded {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isAdded)
                    .opacity(isAdded ? 0.5 : 1)
                }
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func add(_ def: ExerciseDefinition) {
        let nextOrder = (existing.map(\.displayOrder).max() ?? -1) + 1
        let ex = UserExercise.fromCatalog(def, displayOrder: nextOrder)
        context.insert(ex)
    }
}
