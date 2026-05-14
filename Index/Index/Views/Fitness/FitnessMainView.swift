import SwiftUI
import SwiftData

/// Fitness module main screen — feed-only. Brain insight at the top, a
/// one-line "this week" summary, and a chronological list of every
/// non-deleted session. LOG action in the trailing toolbar slot.
///
/// The original scope had quick-start tiles for Cycling / Strength; the
/// redesign drops those in favour of a single LOG entry point that fans
/// out to per-activity log sheets (LogActivitySheet → cycling, running,
/// swimming, squash, other, or strength).
struct FitnessMainView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProfileService.self) private var profileService
    @Environment(HealthKitService.self) private var hkService

    @Query(
        filter: #Predicate<WorkoutSession> { !$0.deletedFromIndex },
        sort: \WorkoutSession.date,
        order: .reverse
    )
    private var sessions: [WorkoutSession]

    @Query(sort: \DailyHealthMetrics.date, order: .reverse)
    private var dailyMetrics: [DailyHealthMetrics]

    @State private var showLogSheet = false

    private var profile: Profile? { profileService.activeProfile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                insightSection
                thisWeekSection
                Divider()
                recentSection
            }
            .padding()
        }
        .navigationTitle("Fitness")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLogSheet = true
                } label: {
                    Text("Log").fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            // P5.19 replaces this with the real LogActivitySheet.
            VStack(spacing: 12) {
                Text("Activity picker").font(.title2.weight(.semibold))
                Text("Coming in P5.19.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .presentationDetents([.medium])
        }
    }

    // MARK: - Brain insight

    @ViewBuilder
    private var insightSection: some View {
        if let insight = BrainService.fitnessInsight(
            thisWeekWorkouts: thisWeekSessions,
            lastWeekWorkouts: lastWeekSessions,
            last7DaysHealth: last7DaysHealth
        ) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.tint)
                Text(insight.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - This week

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This week")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            if thisWeekSessions.isEmpty {
                Text("0 sessions.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(thisWeekSessions.count) sessions · \(formatTotalDuration(thisWeekTotalMinutes)).")
                    .font(.title3.weight(.medium))
            }
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            if sessions.isEmpty {
                emptyState
            } else {
                feedList
            }
        }
    }

    private var emptyState: some View {
        Text("No sessions logged yet.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
    }

    private var feedList: some View {
        List {
            ForEach(sessions) { s in
                Button {
                    // P5.22 wires this row to per-type detail screens.
                } label: {
                    feedRow(s)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(.secondarySystemBackground))
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        s.deletedFromIndex = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(sessions.count) * 64)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func feedRow(_ s: WorkoutSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.type.icon)
                .font(.body)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.type.label)
                    .font(.body)
                Text(relativeWorkoutDate(s.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(formatDuration(s.durationMinutes))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Windowed data

    private var thisWeekSessions: [WorkoutSession] {
        sessions.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .weekOfYear) }
    }

    private var lastWeekSessions: [WorkoutSession] {
        let cal = Calendar.current
        guard let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: .now) else { return [] }
        return sessions.filter { cal.isDate($0.date, equalTo: lastWeek, toGranularity: .weekOfYear) }
    }

    private var last7DaysHealth: [DailyHealthMetrics] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return dailyMetrics.filter { $0.date >= cutoff }
    }

    private var thisWeekTotalMinutes: Int {
        thisWeekSessions.reduce(0) { $0 + $1.durationMinutes }
    }

    // MARK: - Formatters

    private func formatTotalDuration(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    private func formatDuration(_ minutes: Int) -> String {
        formatTotalDuration(minutes)
    }

    /// Today / Yesterday / weekday name (within last week) / "12 May"
    /// (this year) / "12 May 2025" (older years).
    private func relativeWorkoutDate(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }

        let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: .now)).day ?? 0
        if daysAgo > 0, daysAgo < 7 {
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: d)
        }

        let f = DateFormatter()
        f.dateFormat = (cal.component(.year, from: d) == cal.component(.year, from: .now))
            ? "d MMM"
            : "d MMM yyyy"
        return f.string(from: d)
    }
}
