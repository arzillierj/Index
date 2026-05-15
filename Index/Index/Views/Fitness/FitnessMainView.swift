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

    @Query(sort: \StrengthSession.date, order: .reverse)
    private var strengthSessions: [StrengthSession]

    @State private var showLogSheet = false
    @State private var showLogCycling = false
    @State private var logOtherPreset: WorkoutType? = nil
    @State private var showActiveStrength = false
    @State private var showSettings = false
    @State private var selectedSession: WorkoutSession? = nil

    private var profile: Profile? { profileService.activeProfile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageTitle
                if hkService.isBackfilling {
                    backfillBanner
                }
                insightSection
                thisWeekSection
                Divider()
                recentSection
            }
            .padding()
        }
        // Module identity: page-level title in module color; the
        // system nav bar collapses to inline (toolbar buttons only)
        // so the colored "Fitness" hero leads the screen.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showSettings = true
                    } label: {
                        // Explicit Text.secondary breaks the tint
                        // cascade so the gear icon stays neutral.
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(IndexPalette.Text.secondary)
                    }
                    // Manual logging is opt-in (Settings → Manual
                    // logging). Hidden by default for users on Apple
                    // Watch auto-import; the workout feed populates
                    // automatically without a manual entry point.
                    // Tap-to-edit on past sessions stays available.
                    if profile?.manualFitnessLoggingEnabled == true {
                        Button {
                            showLogSheet = true
                        } label: {
                            Text("Log")
                                .fontWeight(.semibold)
                                .foregroundStyle(IndexPalette.Module.fitness)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showLogSheet) {
            LogActivitySheet(onSelect: handleActivityChoice)
        }
        .sheet(isPresented: $showLogCycling) {
            LogCyclingSheet()
        }
        .sheet(item: $logOtherPreset) { preset in
            LogOtherWorkoutSheet(preset: preset)
        }
        .fullScreenCover(isPresented: $showActiveStrength) {
            ActiveStrengthSessionView()
        }
        // State-driven navigation lets the feed rows be Buttons instead
        // of NavigationLinks — Buttons don't reserve trailing space for
        // a system disclosure indicator, so the card extends edge-to-edge
        // and matches the insight pill / This week summary above.
        .navigationDestination(item: $selectedSession) { s in
            detailDestination(for: s)
        }
    }

    /// Routes a LogDestination from LogActivitySheet to the appropriate
    /// sheet or fullScreenCover. Dismissal of the picker is deferred via
    /// a MainActor hop so SwiftUI processes the dismiss before the next
    /// presentation triggers; otherwise iOS can drop the second sheet.
    private func handleActivityChoice(_ dest: LogDestination) {
        showLogSheet = false
        Task { @MainActor in
            switch dest {
            case .strength: showActiveStrength = true
            case .cycling:  showLogCycling = true
            case .running:  logOtherPreset = .running
            case .swimming: logOtherPreset = .swimming
            case .squash:   logOtherPreset = .squash
            case .other:    logOtherPreset = .other
            }
        }
    }

    // MARK: - Page title

    private var pageTitle: some View {
        Text("Fitness")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(IndexPalette.Module.fitness)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Backfill banner

    /// Surfaces during the one-time historical Apple Health workout
    /// backfill (HealthKitService.importHistoricalWorkouts). Disappears
    /// once HealthKitService.isBackfilling flips back to false; rows
    /// stream into the feed below as they're inserted into SwiftData.
    private var backfillBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Importing your Apple Health workouts…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding()
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
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
                    .foregroundStyle(IndexPalette.Module.fitness)
                Text(insight.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding()
            .background(IndexPalette.Surface.card)
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
                // Hero data for Fitness — carries module identity.
                Text("\(thisWeekSessions.count) sessions · \(formatTotalDuration(thisWeekTotalMinutes)).")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(IndexPalette.Module.fitness)
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
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
    }

    private var feedList: some View {
        // VStack-based card to match horizontal insets of the page —
        // List + NavigationLink reserves trailing space for a system
        // disclosure indicator that makes the card end short on the
        // right. Plain Buttons + state-driven navigation avoid the
        // chrome and the card now spans flush with the insight pill
        // and This week summary above.
        VStack(spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { idx, s in
                Button {
                    selectedSession = s
                } label: {
                    feedRow(s)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        s.deletedFromIndex = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                if idx < sessions.count - 1 {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    /// Routes feed row taps to the correct detail screen — strength
    /// sessions get their own view that lists performances + sets, every
    /// other type uses the parameterized WorkoutDetailView.
    @ViewBuilder
    private func detailDestination(for s: WorkoutSession) -> some View {
        if s.type == .strength,
           let strength = strengthSessions.first(where: { $0.id == s.strengthSessionId }) {
            StrengthSessionDetailView(session: strength, workout: s)
        } else {
            WorkoutDetailView(session: s)
        }
    }

    private func feedRow(_ s: WorkoutSession) -> some View {
        HStack(spacing: 12) {
            // Activity icon: explicit module color so it doesn't lose
            // saturation through the hierarchical tint cascade.
            Image(systemName: s.type.icon)
                .font(.body)
                .foregroundStyle(IndexPalette.Module.fitness)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.type.label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(relativeWorkoutDate(s.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Duration is data, not chrome — render near-black so it
            // reads at full strength.
            Text(formatDuration(s.durationMinutes))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.primary)
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
