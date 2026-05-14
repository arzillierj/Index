import SwiftUI
import SwiftData

/// Picker over the user's UserExercise library, used by
/// ActiveStrengthSessionView to switch between exercises mid-session.
/// Tap a row to pick — the sheet dismisses automatically via onPick.
struct ExercisePickerSheet: View {
    let onPick: (UserExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserExercise.displayOrder) private var exercises: [UserExercise]

    var body: some View {
        NavigationStack {
            List {
                ForEach(exercises) { ex in
                    Button {
                        onPick(ex)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).foregroundStyle(.primary)
                            Text(ex.kind.caption)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Pick an exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if exercises.isEmpty {
                    ContentUnavailableView(
                        "No exercises in your library",
                        systemImage: "dumbbell",
                        description: Text("Add some from My exercises first.")
                    )
                }
            }
        }
    }
}
