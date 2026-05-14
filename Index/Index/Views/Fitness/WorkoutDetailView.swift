import SwiftUI
import SwiftData

/// Detail screen for any non-strength WorkoutSession. Cycling, running,
/// swimming, squash, and other all use this view — the stat grid auto-
/// hides fields whose has-flag is false, so a manual squash log shows
/// fewer cells than a HK-imported cycling workout without per-type
/// branching.
///
/// FUTURE: lazy-fetch the HR series + Tanaka zone breakdown from
/// HealthKit when the session has hasHeartRate = true. The v0 pattern
/// is in scope post-v1 once we decide whether the lazy fetch is worth
/// the round trip or we should persist the series with the WorkoutSession
/// (which would be a schema bump).
struct WorkoutDetailView: View {
    let session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                statsGrid
                if session.type == .cycling {
                    routePlaceholder
                }
                if !displayNotes.isEmpty {
                    notesSection
                }
                deleteButton
            }
            .padding()
        }
        .navigationTitle(session.type.label)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this session?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                session.deletedFromIndex = true
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes it from Index. Apple Health is unaffected.")
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(absoluteDateString(session.date))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatDuration(session.durationMinutes))
                    .font(.system(size: 48, weight: .semibold, design: .monospaced))
                Spacer()
                sourceBadge
            }
            if session.hasIntensity {
                Text("Intensity \(session.intensity) / 5")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceBadge: some View {
        Text(session.source == .healthkit ? "Apple Health" : "Manual")
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            if session.hasHeartRate {
                statTile(label: "Avg HR", value: "\(session.avgHeartRate)", unit: "bpm")
            }
            if session.hasMaxHeartRate {
                statTile(label: "Max HR", value: "\(session.maxHeartRate)", unit: "bpm")
            }
            if session.hasKcal {
                statTile(label: "Energy", value: "\(Int(session.kcalBurned.rounded()))", unit: "kcal")
            }
            if session.hasDistance {
                statTile(label: "Distance", value: formatDistance(session.distanceKm), unit: "km")
            }
        }
    }

    private func statTile(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.monospacedDigit())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Route placeholder (cycling only)

    private var routePlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Route")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            ZStack {
                Color(.secondarySystemBackground)
                VStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("Route view coming in a later release.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 120)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - Notes

    /// The session's notes plus any sub-type label that's prefixed there
    /// by LogOtherWorkoutSheet (see DECISION comment in that file).
    private var displayNotes: String { session.notes }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            Text(displayNotes)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
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
        .tint(.red)
    }

    // MARK: - Formatters

    private func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func formatDistance(_ km: Double) -> String {
        km == floor(km) ? "\(Int(km))" : String(format: "%.1f", km)
    }

    private func absoluteDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM yyyy · HH:mm"
        return f.string(from: d)
    }
}
