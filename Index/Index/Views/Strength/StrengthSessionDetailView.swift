import SwiftUI
import SwiftData

/// Past strength session — performances, sets under each, total stats.
/// Delete removes both the StrengthSession and its parallel
/// WorkoutSession (soft-delete on the workout side via deletedFromIndex,
/// hard-delete on the strength side since it owns its child rows).
struct StrengthSessionDetailView: View {
    let session: StrengthSession
    let workout: WorkoutSession?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \UserExercise.displayOrder) private var allExercises: [UserExercise]

    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                summaryGrid
                performancesSection
                if !session.notes.isEmpty {
                    notesSection
                }
                deleteButton
            }
            .padding()
        }
        .navigationTitle("Strength")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deleteSession)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the workout and every set logged inside it.")
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(absoluteDateString(session.date))
                .font(IndexFont.heroCaption)
                .foregroundStyle(.secondary)
            Text(formatDuration(session.durationMinutes))
                .font(IndexFont.hero)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            statTile(label: "Exercises", value: "\(session.orderedPerformances.count)")
            statTile(label: "Sets", value: "\(totalSets)")
        }
    }

    /// Section 4 layout-hardening: numeral scales down under
    /// Dynamic Type / long values rather than clipping.
    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(IndexFont.tileLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(IndexFont.tileValue)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Performances

    private var performancesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EXERCISES")
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            VStack(spacing: 12) {
                ForEach(session.orderedPerformances) { perf in
                    performanceBlock(perf)
                }
            }
        }
    }

    private func performanceBlock(_ perf: ExercisePerformance) -> some View {
        let name = allExercises.first(where: { $0.id == perf.userExerciseId })?.name ?? "Unknown exercise"
        return VStack(alignment: .leading, spacing: 8) {
            Text(name).font(IndexFont.rowTitle.weight(.medium))
            VStack(spacing: 0) {
                ForEach(perf.orderedSets.indices, id: \.self) { i in
                    let set = perf.orderedSets[i]
                    HStack {
                        Text("Set \(i + 1)")
                            .font(IndexFont.rowSecondary)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        Text("\(formatKg(set.weightKg)) kg × \(set.reps)")
                            .font(IndexFont.rowValue)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    if i < perf.orderedSets.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOTES")
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            Text(session.notes)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(IndexPalette.Surface.card)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete session")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(IndexPalette.Action.destructive)
    }

    // MARK: - Actions

    private func deleteSession() {
        // Soft-delete the parallel WorkoutSession (so HK auto-import
        // tombstoning works) and hard-delete the StrengthSession (which
        // cascade-deletes its performances + sets).
        if let workout {
            workout.deletedFromIndex = true
        }
        context.delete(session)
        dismiss()
    }

    // MARK: - Computed

    private var totalSets: Int {
        session.orderedPerformances.reduce(0) { $0 + $1.orderedSets.count }
    }

    private func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func absoluteDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM yyyy · HH:mm"
        return f.string(from: d)
    }

    private func formatKg(_ kg: Double) -> String {
        SafeFormat.decimal(kg)
    }
}
