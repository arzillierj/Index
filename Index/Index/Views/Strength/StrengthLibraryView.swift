import SwiftUI
import SwiftData

/// The user's personal exercise library. Reached from LogActivitySheet
/// "My exercises". Tapping a row pushes ExerciseDetailView; swipe deletes
/// the row from the library (does NOT delete past session history —
/// SetEntry rows belong to ExercisePerformance / StrengthSession).
struct StrengthLibraryView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<UserExercise> { !$0.hiddenFromLibrary },
        sort: \UserExercise.displayOrder
    )
    private var exercises: [UserExercise]

    @State private var showAdd = false

    var body: some View {
        Group {
            if exercises.isEmpty {
                ContentUnavailableView(
                    "No exercises yet",
                    systemImage: "dumbbell",
                    description: Text("Tap + to pick from the starter catalog.")
                )
            } else {
                List {
                    ForEach(exercises) { ex in
                        NavigationLink {
                            ExerciseDetailView(exercise: ex)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name)
                                Text(ex.kind.caption)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                // Audit DQ4 — soft-hide instead of
                                // hard-delete. Past session history
                                // still resolves the exercise name
                                // via the userExerciseId soft-link;
                                // re-adding from AddExerciseSheet
                                // un-hides the same row.
                                ex.hiddenFromLibrary = true
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("My exercises")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExerciseSheet()
        }
    }
}
