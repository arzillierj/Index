import SwiftUI
import SwiftData

/// Picker over the 10-exercise starter catalog. Rows already in the user's
/// library show a checkmark and are disabled so a tap on an unrelated row
/// is unambiguous.
struct AddExerciseSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Unfiltered intentionally — the duplicate check below counts
    /// hidden rows too so a previously-removed catalog id un-hides
    /// instead of inserting a duplicate (audit DQ4).
    @Query(sort: \UserExercise.displayOrder) private var existing: [UserExercise]

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCatalog.starter) { def in
                    // "Added" = present and visible. A hidden row is
                    // re-addable (tap un-hides it).
                    let visibleMatch = existing.first { $0.id == def.id && !$0.hiddenFromLibrary }
                    let isAdded = visibleMatch != nil
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
        // If a hidden row for this catalog id already exists, un-hide
        // it instead of inserting a duplicate (audit DQ4). Catalog ids
        // are deterministic and become UserExercise.id verbatim, so
        // duplicate inserts would break ExercisePerformance.userExerciseId
        // → UserExercise.id soft-link resolution in old session history.
        if let existingHidden = existing.first(where: { $0.id == def.id && $0.hiddenFromLibrary }) {
            existingHidden.hiddenFromLibrary = false
            return
        }
        let nextOrder = (existing.map(\.displayOrder).max() ?? -1) + 1
        let ex = UserExercise.fromCatalog(def, displayOrder: nextOrder)
        context.insert(ex)
    }
}
