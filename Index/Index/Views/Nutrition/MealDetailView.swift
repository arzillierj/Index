import SwiftUI
import SwiftData

/// Read view for a single NutritionEntry with Edit and Delete actions.
/// Edit delegates back to the parent via `onRequestEdit` — the parent
/// dismisses this sheet first, then presents LogMealManualSheet pre-filled
/// (sheet-then-sheet sequencing requires onDismiss coordination, which
/// the parent handles). Delete hard-deletes after a confirmation dialog.
struct MealDetailView: View {
    let entry: NutritionEntry
    let onRequestEdit: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    labelRow("Label", entry.label.isEmpty ? "—" : entry.label)
                    labelRow("Meal", entry.mealType.label)
                    labelRow("When", fullDateString(entry.date))
                    labelRow("Source", sourceLabel(entry.source))
                }

                Section("Macros") {
                    numericRow("Calories", "\(SafeFormat.int(entry.kcal)) kcal")
                    numericRow("Protein",  "\(SafeFormat.int(entry.protein)) g")
                    numericRow("Carbs",    "\(SafeFormat.int(entry.carbs)) g")
                    numericRow("Fat",      "\(SafeFormat.int(entry.fat)) g")
                }

                Section {
                    Button("Edit") {
                        onRequestEdit()
                        dismiss()
                    }
                    Button("Delete", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this meal?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func labelRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func numericRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }

    private func delete() {
        context.delete(entry)
        dismiss()
    }

    private func sourceLabel(_ s: NutritionSource) -> String {
        switch s {
        case .manual:  "Manual"
        case .barcode: "Barcode"
        case .photo:   "Photo"
        }
    }

    private func fullDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM · HH:mm"
        return f.string(from: d)
    }
}
