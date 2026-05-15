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
        sort: \NutritionEntry.date,
        order: .reverse
    )
    private var allEntries: [NutritionEntry]
    // NutritionEntry.deletedFromIndex is deprecated — the swipe path
    // hard-deletes via context.delete(entry), so there are no
    // tombstoned rows for the predicate to filter out.

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

    @State private var showScanner = false
    @State private var showSettings = false
    @State private var manualEntryPrefill: ManualEntryPrefill? = nil
    @State private var selectedEntry: NutritionEntry? = nil
    @State private var editTarget: NutritionEntry? = nil
    @State private var scannedBarcode: ScannedBarcode? = nil
    @State private var pendingEditTarget: NutritionEntry? = nil
    @State private var pendingScannedBarcode: String? = nil
    @State private var pendingFallbackBarcode: String? = nil

    /// .sheet(item:) wrappers — small Identifiable shells so the same
    /// sheet slot can route to either a fresh entry, a barcode-fallback
    /// entry (manual, label-only), or a frequent-foods chip tap
    /// (label + full macros pre-filled), and so the result sheet's item
    /// drives presentation.
    struct ManualEntryPrefill: Identifiable {
        let id = UUID()
        let label: String?
        var kcal: Double? = nil
        var protein: Double? = nil
        var carbs: Double? = nil
        var fat: Double? = nil
    }
    struct ScannedBarcode: Identifiable {
        let id: String
        var code: String { id }
    }

    private var profile: Profile? { profileService.activeProfile }

    var body: some View {
        // Audit H18 — derive once per body and thread through the
        // subsections that need it. Avoids 4× MetricsEngine.dailyTargets
        // recomputation per render (insight + hero Calories + hero
        // Protein + workoutCaption all needed it before).
        let targets = computedTargets
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageTitle
                heroRow(targets: targets)
                macroGrid
                actionRow
                frequentChipsSection
                todaysLogSection
            }
            .padding()
        }
        // Module identity: page-level title takes the module color;
        // the system nav-bar collapses to inline (toolbar buttons
        // only) so the colored "Nutrition" hero leads the screen.
        .navigationBarTitleDisplayMode(.inline)
        // DECISION: No toolbar "Log" button. Phase 6 ships with two
        // first-class action buttons on the main screen itself (Scan
        // barcode / Enter manually) — duplicating either as a toolbar
        // shortcut creates a "which one does it open?" ambiguity. The
        // two on-screen buttons are anchored above the daily log so
        // they remain thumb-reachable without scrolling. Phase 7
        // adds the gear icon for Settings — top-right alone since
        // there's no Log button competing for the slot.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    // Explicit Text.secondary breaks the tint cascade.
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(IndexPalette.Text.secondary)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $manualEntryPrefill) { prefill in
            LogMealManualSheet(
                editing: nil,
                prefilledLabel: prefill.label,
                prefilledKcal: prefill.kcal,
                prefilledProtein: prefill.protein,
                prefilledCarbs: prefill.carbs,
                prefilledFat: prefill.fat
            )
        }
        .sheet(item: $selectedEntry, onDismiss: routeAfterDetailSheet) { entry in
            MealDetailView(entry: entry, onRequestEdit: {
                pendingEditTarget = entry
            })
        }
        .sheet(item: $editTarget) { entry in
            LogMealManualSheet(editing: entry)
        }
        .sheet(item: $scannedBarcode, onDismiss: routeAfterResultSheet) { wrapper in
            BarcodeResultSheet(
                barcode: wrapper.code,
                onFallbackToManual: { code in
                    pendingFallbackBarcode = code
                    scannedBarcode = nil
                }
            )
        }
        .fullScreenCover(isPresented: $showScanner, onDismiss: routeAfterScanner) {
            BarcodeScannerView(
                onDetect: { code in
                    pendingScannedBarcode = code
                    showScanner = false
                },
                onCancel: { showScanner = false }
            )
        }
    }

    // MARK: - Page title

    private var pageTitle: some View {
        Text("Nutrition")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(IndexPalette.Module.nutrition)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 12) {
            actionButton(
                title: "Scan barcode",
                icon: "barcode.viewfinder",
                action: { showScanner = true }
            )
            actionButton(
                title: "Enter manually",
                icon: "square.and.pencil",
                action: { manualEntryPrefill = ManualEntryPrefill(label: nil) }
            )
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // Icon picks up the Nutrition module accent (teal). Text
                // stays near-black so the label reads at default contrast
                // and the icon carries the module identity on its own.
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(IndexPalette.Module.nutrition)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sheet sequencing
    //
    // iOS won't present a new sheet while the prior is still dismissing.
    // Each transition (detail → edit, scanner → result, result → manual
    // fallback) sets a "pending" intent and arms it from the dismissed
    // sheet's `onDismiss`.

    private func routeAfterDetailSheet() {
        guard let entry = pendingEditTarget else { return }
        pendingEditTarget = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            editTarget = entry
        }
    }

    private func routeAfterScanner() {
        guard let code = pendingScannedBarcode else { return }
        pendingScannedBarcode = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            scannedBarcode = ScannedBarcode(id: code)
        }
    }

    private func routeAfterResultSheet() {
        guard let code = pendingFallbackBarcode else { return }
        pendingFallbackBarcode = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            manualEntryPrefill = ManualEntryPrefill(label: "Barcode \(code)")
        }
    }

    // MARK: - Hero row (Calories + Protein side-by-side)
    //
    // Two equal-width hero stacks. Calories on the left (with the optional
    // workout-adjustment caption), Protein on the right. Equal visual
    // weight communicates "the two metrics that matter most for cutting"
    // — neither dominates.
    //
    // Cards intentionally absent from the hero (unlike Carbs / Fat
    // tiles below). The numbers float on the page background; the hero
    // dominates by typography rather than chrome. Vertical breathing
    // room compensates for the missing card padding so the hero
    // doesn't crowd the "TODAY" caption above or the macro grid below.
    //
    // Big number wraps to its own line above the "/ target unit" subtitle
    // (rather than HStack-ing them) so a 4-digit consumed + 4-digit target
    // doesn't crowd at iPhone SE widths. minimumScaleFactor protects
    // against the worst case if the number ever grows past 4 digits.

    private func heroRow(targets: DailyTargets?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            HStack(alignment: .top, spacing: 10) {
                heroCell(
                    label: "Calories",
                    consumed: todayKcal,
                    target: targets?.calories ?? 0,
                    unit: "kcal",
                    caption: workoutCaption(targets: targets)
                )
                heroCell(
                    label: "Protein",
                    consumed: todayProtein,
                    target: targets?.protein ?? 0,
                    unit: "g",
                    caption: nil
                )
            }
            .padding(.bottom, 8)
        }
    }

    private func heroCell(
        label: String,
        consumed: Double,
        target: Double,
        unit: String,
        caption: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            // Hero numeral takes the Nutrition module color — both
            // Calories and Protein are co-equal heroes for cutting.
            Text(SafeFormat.int(consumed))
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .foregroundStyle(IndexPalette.Module.nutrition)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("/ \(SafeFormat.int(target)) \(unit)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // Caption slot is always rendered (invisible when nil) so
            // both cells remain the same height side-by-side.
            Text(caption ?? " ")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .opacity(caption == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workoutCaption(targets: DailyTargets?) -> String? {
        // MetricsEngine zeros workoutCalories when the
        // eat-back-workout-calories toggle is off, so the > 0 guard
        // alone is enough to hide the caption when the workout
        // contribution isn't actually applied.
        guard let kcal = targets?.workoutCalories, kcal > 0 else { return nil }
        return "+\(SafeFormat.int(kcal)) kcal from workouts"
    }

    // MARK: - Frequent foods chips (behavior-based, last 30 days)
    //
    // No explicit favorites. Top 5 most-frequent labels logged in the
    // last 30 days; chip tap pre-fills LogMealManualSheet with the most
    // recent entry's macros. Hidden when fewer than 3 distinct items
    // qualify (new user / very varied diet).

    @ViewBuilder
    private var frequentChipsSection: some View {
        let chips = frequentChips
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Frequent")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            frequentChipButton(chip)
                        }
                    }
                    // Padding prevents shadow / focus-ring clipping at
                    // the row edges when chips overflow.
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func frequentChipButton(_ chip: FrequentChipData) -> some View {
        Button {
            manualEntryPrefill = ManualEntryPrefill(
                label: chip.label,
                kcal: chip.kcal,
                protein: chip.protein,
                carbs: chip.carbs,
                fat: chip.fat
            )
        } label: {
            Text(chip.label)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(Capsule().fill(IndexPalette.Surface.divider))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private struct FrequentChipData: Identifiable {
        let id = UUID()
        let label: String
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    /// Group last-30-day entries by lowercased+trimmed label, take top 5
    /// by count, hide when fewer than 3 distinct items qualify. Chip
    /// pre-fill macros come from the *most recent* entry of each group
    /// (per spec: when the same label has different macros across days,
    /// most recent wins — user can adjust before saving).
    private var frequentChips: [FrequentChipData] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .distantPast
        let recent = allEntries.filter { entry in
            entry.date >= cutoff
                && !entry.label.trimmingCharacters(in: .whitespaces).isEmpty
        }
        var groups: [String: [NutritionEntry]] = [:]
        for entry in recent {
            let key = entry.label.lowercased().trimmingCharacters(in: .whitespaces)
            groups[key, default: []].append(entry)
        }
        let sortedGroups = groups.values.sorted { $0.count > $1.count }
        let top5 = Array(sortedGroups.prefix(5))
        guard top5.count >= 3 else { return [] }
        return top5.compactMap { entries -> FrequentChipData? in
            guard let mostRecent = entries.max(by: { $0.date < $1.date }) else { return nil }
            return FrequentChipData(
                label: mostRecent.label,
                kcal: mostRecent.kcal,
                protein: mostRecent.protein,
                carbs: mostRecent.carbs,
                fat: mostRecent.fat
            )
        }
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
        .background(IndexPalette.Surface.card)
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
                    .background(IndexPalette.Surface.card)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                todayList
            }
        }
    }

    private var todayList: some View {
        // VStack-based card so the right-edge inset matches the rest
        // of the page; List reserves a scrollbar gutter on the
        // trailing side. ContextMenu (long-press) replaces swipe for
        // delete. Hard-delete still applies — nutrition rows never
        // mirror to HealthKit so a tombstone serves no dedup purpose.
        let rows = todayEntries
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, entry in
                Button {
                    selectedEntry = entry
                } label: {
                    row(entry: entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        context.delete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                if idx < rows.count - 1 {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(IndexPalette.Surface.card)
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
            // kcal is a data value — render at full strength so it
            // reads cleanly against the card background.
            Text("\(SafeFormat.int(entry.kcal)) kcal")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
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
