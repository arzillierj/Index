import SwiftUI
import SwiftData

/// Nutrition module main screen. Brain insight at the top, "Today" hero
/// with calories + protein vs target, macro grid (carbs / fat), and a
/// chronological list of today's entries with swipe-to-delete.
///
/// LOG button in the navigation bar opens a placeholder sheet — the real
/// log-method picker lands in Phase 6 step 26.
struct NutritionMainView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProfileService.self) private var profileService

    @Query(
        filter: #Predicate<NutritionEntry> { !$0.deletedFromIndex },
        sort: \NutritionEntry.date,
        order: .reverse
    )
    private var allEntries: [NutritionEntry]

    @Query(
        filter: #Predicate<WeightEntry> { !$0.deletedFromIndex },
        sort: \WeightEntry.date,
        order: .reverse
    )
    private var weights: [WeightEntry]

    @Query(
        filter: #Predicate<WorkoutSession> { !$0.deletedFromIndex },
        sort: \WorkoutSession.date,
        order: .reverse
    )
    private var workouts: [WorkoutSession]

    @State private var showLogMethod = false
    @State private var showManualEntry = false
    @State private var selectedEntry: NutritionEntry? = nil
    @State private var editTarget: NutritionEntry? = nil
    @State private var pendingAfterMethod: PendingAfterMethod? = nil
    @State private var pendingEditTarget: NutritionEntry? = nil
    @State private var showScannerNotReady = false

    private enum PendingAfterMethod { case manual, scan }

    private var profile: Profile? { profileService.activeProfile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                insightSection
                todayHero
                macroGrid
                todaysLogSection
            }
            .padding()
        }
        .navigationTitle("Nutrition")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLogMethod = true
                } label: {
                    Text("Log").fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showLogMethod, onDismiss: routeAfterMethodSheet) {
            LogMealMethodSheet { method in
                pendingAfterMethod = (method == .scan) ? .scan : .manual
                showLogMethod = false
            }
        }
        .sheet(isPresented: $showManualEntry) {
            LogMealManualSheet(editing: nil)
        }
        .sheet(item: $selectedEntry, onDismiss: routeAfterDetailSheet) { entry in
            MealDetailView(entry: entry, onRequestEdit: {
                pendingEditTarget = entry
            })
        }
        .sheet(item: $editTarget) { entry in
            LogMealManualSheet(editing: entry)
        }
        .alert(
            "Scanner coming in step 27",
            isPresented: $showScannerNotReady
        ) {
            Button("OK") {}
        }
    }

    // MARK: - Sheet sequencing
    //
    // iOS won't present a new sheet while the prior is still dismissing.
    // Each transition (method → manual, detail → edit) sets a "pending"
    // intent and arms it from the dismissed sheet's `onDismiss`.

    private func routeAfterMethodSheet() {
        guard let action = pendingAfterMethod else { return }
        pendingAfterMethod = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            switch action {
            case .manual: showManualEntry = true
            case .scan:   showScannerNotReady = true
            }
        }
    }

    private func routeAfterDetailSheet() {
        guard let entry = pendingEditTarget else { return }
        pendingEditTarget = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            editTarget = entry
        }
    }

    // MARK: - Brain insight

    @ViewBuilder
    private var insightSection: some View {
        if let profile,
           let targets = computedTargets,
           let insight = BrainService.nutritionInsight(
                profile: profile,
                targets: targets,
                todayEntries: todayEntries,
                recentEntries: recentEntries,
                todaysWorkouts: todaysWorkouts
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

    // MARK: - Today hero

    private var todayHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)

            heroLine(
                label: "Calories",
                consumed: todayKcal,
                target: computedTargets?.calories ?? 0,
                unit: "kcal",
                caption: workoutCaption
            )

            heroLine(
                label: "Protein",
                consumed: todayProtein,
                target: computedTargets?.protein ?? 0,
                unit: "g",
                caption: nil
            )
        }
    }

    private func heroLine(
        label: String,
        consumed: Double,
        target: Double,
        unit: String,
        caption: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SafeFormat.int(consumed))
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                Text("/ \(SafeFormat.int(target)) \(unit)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var workoutCaption: String? {
        guard let kcal = computedTargets?.workoutCalories, kcal > 0 else { return nil }
        return "+\(SafeFormat.int(kcal)) kcal from workouts"
    }

    // MARK: - Macro grid

    private var macroGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ],
            spacing: 10
        ) {
            macroTile(label: "Carbs", value: todayCarbs)
            macroTile(label: "Fat", value: todayFat)
        }
    }

    private func macroTile(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(SafeFormat.int(value))
                    .font(.title3.monospacedDigit())
                Text("g")
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

    // MARK: - Today's log

    private var todaysLogSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today's log")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            if todayEntries.isEmpty {
                Text("No entries today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                todayList
            }
        }
    }

    private var todayList: some View {
        let rows = todayEntries
        return List {
            ForEach(rows) { entry in
                Button {
                    selectedEntry = entry
                } label: {
                    row(entry: entry)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(.secondarySystemBackground))
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        // Hard delete: nutrition data never mirrors to
                        // HealthKit (Index doesn't write food back), so
                        // there's no dedup reason to keep a tombstone.
                        context.delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .frame(height: CGFloat(rows.count) * 64)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func row(entry: NutritionEntry) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(mealTypeLabel(entry.mealType))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    Text(entry.label.isEmpty ? "—" : entry.label)
                        .font(.body)
                        .lineLimit(1)
                }
                Text(timeString(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("\(SafeFormat.int(entry.kcal)) kcal")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Derived data

    private var todayEntries: [NutritionEntry] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? .now
        return allEntries.filter { $0.date >= start && $0.date < end }
    }

    /// Last 7 days powers the BrainService nutrition rules — low-protein
    /// looks at the previous 3 days, meal-gap fallback walks back further
    /// when today is empty.
    private var recentEntries: [NutritionEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .distantPast
        return allEntries.filter { $0.date >= cutoff }
    }

    private var todaysWorkouts: [WorkoutSession] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? .now
        return workouts.filter { $0.date >= start && $0.date < end }
    }

    private var last14DaysWeight: [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .distantPast
        return weights.filter { $0.date >= cutoff }
    }

    private var todayKcal:    Double { todayEntries.reduce(0) { $0 + $1.kcal } }
    private var todayProtein: Double { todayEntries.reduce(0) { $0 + $1.protein } }
    private var todayCarbs:   Double { todayEntries.reduce(0) { $0 + $1.carbs } }
    private var todayFat:     Double { todayEntries.reduce(0) { $0 + $1.fat } }

    /// Computed once per `body` evaluation; passed into both the hero and
    /// the brain insight rule. Mirrors the v0 M1 audit fix (don't
    /// recompute targets per re-render).
    private var computedTargets: DailyTargets? {
        guard let profile else { return nil }
        return MetricsEngine.dailyTargets(
            profile: profile,
            latestWeight: weights.first,
            todaysWorkouts: todaysWorkouts,
            last14DaysWeight: last14DaysWeight
        )
    }

    private func mealTypeLabel(_ m: MealType) -> String {
        switch m {
        case .breakfast: "BREAKFAST"
        case .lunch:     "LUNCH"
        case .dinner:    "DINNER"
        case .snack:     "SNACK"
        }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
