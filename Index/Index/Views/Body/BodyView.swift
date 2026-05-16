import SwiftUI
import SwiftData
import Charts

/// Body module main screen. Brain insight at the top, hero weight, 30-day
/// trend chart, metric tiles, vitals tiles, recent entries. LOG action
/// lives in the navigation bar trailing slot.
///
/// System default styling — visual design pass lands later as a separate
/// prompt.
struct BodyView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProfileService.self) private var profileService
    @Environment(HealthKitService.self) private var hkService

    @Query(
        filter: #Predicate<WeightEntry> { !$0.deletedFromIndex },
        sort: \WeightEntry.date,
        order: .reverse
    )
    private var weights: [WeightEntry]

    @Query(sort: \DailyHealthMetrics.date, order: .reverse)
    private var dailyMetrics: [DailyHealthMetrics]

    @State private var showLogSheet = false
    @State private var showSettings = false
    @State private var selectedEntry: WeightEntry? = nil

    private var profile: Profile? { profileService.activeProfile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                pageTitle
                insightSection
                heroWeight
                trendChart
                metricsSection
                vitalsSection
                recentEntriesSection
            }
            .padding()
        }
        // Module identity: page-level title takes the module color
        // instead of the system nav-bar title. Inline display mode
        // keeps the system bar slim (just the toolbar items) so the
        // colored "Body" hero text is the first thing on screen.
        .navigationBarTitleDisplayMode(.inline)
        // Top safe-area inset (regression fix on top of the layout
        // commit). Passing `.visible` was insufficient under iOS 26
        // Liquid Glass — the inline nav bar still rendered a
        // translucent material, letting scrolling page content show
        // through the status-bar region. An EXPLICIT Color
        // (`IndexPalette.Surface.background`) makes the nav bar
        // background fully opaque and matches the page surface, so
        // scroll content stops at the safe-area edge.
        .toolbarBackground(IndexPalette.Surface.background, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showSettings = true
                    } label: {
                        // Explicit Text.secondary breaks the tint cascade
                        // so the gear stays neutral on a tinted tab.
                        Image(systemName: "gearshape")
                            .font(.title3)
                            .foregroundStyle(IndexPalette.Text.secondary)
                    }
                    // Manual logging is opt-in (Settings → Manual
                    // logging). Hidden by default so users who write
                    // weight from RENPHO via HealthKit aren't shown a
                    // redundant entry point. HK auto-imports +
                    // tap-to-edit history rows still work either way.
                    if profile?.manualWeightLoggingEnabled == true {
                        Button {
                            showLogSheet = true
                        } label: {
                            Text("Log")
                                .fontWeight(.semibold)
                                .foregroundStyle(IndexPalette.Module.body)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogWeightSheet()
        }
        .sheet(item: $selectedEntry) { entry in
            WeightEntryDetailSheet(entry: entry)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Page title

    private var pageTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Body")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(IndexPalette.Module.body)
            // Demo-mode pill — collapses to EmptyView when the
            // flag is off, so the title sits exactly where it
            // did before in normal mode.
            DemoBadge()
            Spacer(minLength: 0)
        }
        // Breathing room above the cap-height — without it
        // the glyph tops sit flush against the safe-area
        // boundary and read as clipped at the top edge.
        .padding(.top, 6)
    }

    // MARK: - Brain insight

    @ViewBuilder
    private var insightSection: some View {
        if let profile,
           let insight = BrainService.bodyInsight(
            profile: profile,
            last14DaysWeight: weightsInLastDays(14),
            last7DaysHealth: dailyMetricsInLastDays(7)
           ) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkle")
                    .foregroundStyle(IndexPalette.Module.body)
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

    // MARK: - Hero weight

    private var heroWeight: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest weight")
                .font(IndexFont.tileLabel)
                .foregroundStyle(.secondary)
            if let latest = weights.first {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatKg(latest.weightKg))
                        .font(IndexFont.hero)
                        .foregroundStyle(IndexPalette.Module.body)
                    Text("kg")
                        .font(IndexFont.heroUnit)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text(relativeDateString(latest.date))
                        .font(IndexFont.heroCaption)
                        .foregroundStyle(.secondary)
                    if let delta = computeWeightDelta() {
                        deltaLabel(delta)
                    }
                }
            } else {
                Text("—")
                    .font(IndexFont.hero)
                    .foregroundStyle(.tertiary)
                Text("Tap Log to add your first entry.")
                    .font(IndexFont.heroCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deltaLabel(_ kgDelta: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: kgDelta < 0 ? "arrow.down" : "arrow.up")
                .font(.caption2)
            Text("\(formatKg(abs(kgDelta))) kg")
                .font(IndexFont.heroCaption)
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Trend chart

    @ViewBuilder
    private var trendChart: some View {
        let series = weightsInLastDays(30).sorted { $0.date < $1.date }
        if series.count >= 2 {
            let domain = weightDomain(series)
            Chart {
                ForEach(series, id: \.persistentModelID) { entry in
                    // Explicit yStart at the visible-domain floor —
                    // without it, AreaMark baselines at y=0 (Swift
                    // Charts' default for a numeric axis). Combined
                    // with chartYScale(domain: lo...hi) where lo is
                    // ~86 kg, the area used to draw from y=0 up to
                    // the data point and then be clipped imperfectly
                    // by the chart frame — the gradient bled outside
                    // the chart bounds and tinted the entire screen
                    // (COMPOSITION / VITALS / RECENT ENTRIES). Binding
                    // the area to the visible domain's lower bound
                    // contains the fill where it should be.
                    AreaMark(
                        x: .value("Date", entry.date),
                        yStart: .value("Floor", domain.lowerBound),
                        yEnd: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [IndexPalette.Module.body.opacity(0.25), IndexPalette.Module.body.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(IndexPalette.Module.body)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: chartStrideDays(series))) { _ in
                    AxisGridLine()
                    AxisTick()
                    // Always show date-only, abbreviated month. Without an
                    // explicit format Swift Charts auto-scales to hours
                    // when the data range is short ("12 May at 23").
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 180)
            // Belt-and-suspenders against the previous gradient-bleed
            // regression — even with the bounded AreaMark above, clip
            // anything that might overdraw the chart frame so nothing
            // ever escapes the chart's rectangle again.
            .clipped()
        } else {
            Text("Log more weights to see your trend.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(IndexPalette.Surface.card)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    /// Auto-range the weight chart's y-axis to the visible data
    /// instead of letting Swift Charts default to 0…(max + pad).
    /// Real-world weight series sit in a narrow band (87.3–87.5
    /// kg) — a 0-based axis collapses them to a flat line pinned
    /// to the top of the chart and the whole point of the trend
    /// is invisible.
    ///
    /// Padding rule mirrors the swim-detail HR chart (audit
    /// reference implementation): take the data's [min, max],
    /// pad each side by max(15% of range, 0.5 kg). The fixed
    /// floor handles ultra-tight data — two weigh-ins one decigram
    /// apart still need a visible y-range. Single-point case is
    /// guarded upstream by `series.count >= 2`.
    private func weightDomain(_ series: [WeightEntry]) -> ClosedRange<Double> {
        let values = series.map(\.weightKg)
        guard let lo = values.min(), let hi = values.max() else {
            return 0...100
        }
        let span = hi - lo
        let pad = max(span * 0.15, 0.5)
        return (lo - pad)...(hi + pad)
    }

    /// Day-stride between x-axis ticks, scaled to aim for ~4 ticks across
    /// the visible range. Prevents truncated labels at short ranges
    /// (where every-day ticks would crowd) and at long ranges (where
    /// every-day ticks would overflow).
    private func chartStrideDays(_ series: [WeightEntry]) -> Int {
        guard let first = series.first, let last = series.last else { return 1 }
        let days = max(1, Int(last.date.timeIntervalSince(first.date) / 86400))
        return max(1, days / 4)
    }

    // MARK: - Metrics grid

    private var metricsSection: some View {
        // Audit H18 — pre-compute text values used twice in the unit
        // ternaries so the second access doesn't re-walk the
        // MetricsEngine math + weights/profile lookups.
        let bodyFat  = bodyFatText
        let leanMass = leanMassText
        return VStack(alignment: .leading, spacing: 10) {
            Text("COMPOSITION")
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                // BMI / BMR / TDEE / Ideal range are descriptive
                // metrics — coloring "up vs. down" would lie about
                // good vs. bad (a higher TDEE isn't intrinsically
                // good or bad; BMI can move either direction
                // toward healthy depending on the user). No delta
                // here. The two composition metrics with an honest
                // direction-of-good (body fat down / lean mass up)
                // get the indicator.
                tile(label: "BMI", value: bmiText, unit: nil)
                tile(label: "BMR", value: bmrText, unit: "kcal")
                tile(label: "TDEE", value: tdeeText, unit: "kcal")
                tile(label: "Body fat", value: bodyFat, unit: bodyFat == "—" ? nil : "%", delta: bodyFatDelta)
                tile(label: "Lean mass", value: leanMass, unit: leanMass == "—" ? nil : "kg", delta: leanMassDelta)
                tile(label: "Ideal range", value: idealRangeText, unit: "kg")
            }
        }
    }

    private var vitalsSection: some View {
        // Audit H18 — pre-compute text values used twice in the unit
        // ternaries (same pattern as metricsSection above).
        let hrv = hrvText
        let rhr = rhrText
        return VStack(alignment: .leading, spacing: 10) {
            Text("VITALS")
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                tile(label: "HRV", value: hrv, unit: hrv == "—" ? nil : "ms", delta: hrvDelta)
                tile(label: "VO2 max", value: vo2Text, unit: nil, delta: vo2Delta)
                tile(label: "Resting HR", value: rhr, unit: rhr == "—" ? nil : "bpm", delta: rhrDelta)
            }
        }
    }

    /// Display-only tile. Metric explanation overlays were explicitly cut
    /// from v2 (see CLAUDE.md "Things explicitly NOT in v1"). The value
    /// speaks for itself; no tap target.
    ///
    /// Section 4 layout-hardening: the value+unit pair is one unit
    /// that must fit on a single line. The numeral scales down via
    /// `minimumScaleFactor(0.6)`; the unit gets `layoutPriority(1)`
    /// so when space is tight, the numeral shrinks rather than the
    /// "kg" / "kcal" / "%" clipping at the tile's trailing edge. A
    /// long composite like "74–90" with a "kg" trailing unit now
    /// fits in the half-width composition tiles at default text size
    /// AND under Dynamic Type's larger steps.
    private func tile(
        label: String,
        value: String,
        unit: String?,
        delta: TileDelta? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(IndexFont.tileLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(IndexFont.tileValue)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(IndexFont.tileUnit)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            if let delta {
                deltaIndicator(delta)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    /// Direction-of-good arrow + absolute change inside a tile.
    /// The ARROW shows where the number moved (up arrow = value
    /// increased). The COLOR shows whether that movement was good
    /// for the user. Body fat dropping renders a green DOWN
    /// arrow, lean mass rising renders a green UP arrow, resting
    /// HR rising renders a red UP arrow, etc.
    ///
    /// Uses `IndexFont.tileUnit` so the indicator reads as a
    /// quiet sibling of the unit label rather than competing
    /// with the tile value. `monospacedDigit()` keeps numerics
    /// column-aligned across a grid row.
    private func deltaIndicator(_ delta: TileDelta) -> some View {
        HStack(spacing: 3) {
            Image(systemName: delta.arrowSystemName)
                .font(IndexFont.tileUnit)
            Text("\(delta.formattedAbs) \(delta.unit)")
                .font(IndexFont.tileUnit)
                .monospacedDigit()
        }
        .foregroundStyle(delta.isGood ? IndexPalette.Semantic.success : IndexPalette.Semantic.error)
        .lineLimit(1)
    }

    // MARK: - Recent entries

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT ENTRIES")
                    .font(IndexFont.sectionCap)
                    .kerning(0.8)
                    .foregroundStyle(IndexPalette.Text.tertiary)
                Spacer()
                NavigationLink {
                    WeightHistoryView()
                } label: {
                    Text("See all")
                        .font(IndexFont.rowSecondary)
                }
            }
            if weights.isEmpty {
                Text("No entries yet.")
                    .font(IndexFont.rowSecondary)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(IndexPalette.Surface.card)
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                recentEntriesList
            }
        }
    }

    /// List wrapper that gives recent entries swipe-to-delete behavior
    /// matching the full-history screen. The List is scroll-disabled and
    /// sized to its rows so it nests cleanly in the outer ScrollView
    /// — .swipeActions is a List-only modifier, so we can't use a plain
    /// VStack here.
    private var recentEntriesList: some View {
        // VStack-based card so the right-edge inset matches the rest
        // of the screen (page padding); a plain List reserves a
        // scrollbar gutter on the trailing side even with scrolling
        // disabled. ContextMenu replaces swipeActions for delete.
        let recent = Array(weights.prefix(5))
        return VStack(spacing: 0) {
            ForEach(Array(recent.enumerated()), id: \.element.id) { idx, entry in
                Button {
                    selectedEntry = entry
                } label: {
                    recentEntryRow(entry: entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        entry.deletedFromIndex = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                if idx < recent.count - 1 {
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func recentEntryRow(entry: WeightEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatKg(entry.weightKg))
                        .font(IndexFont.rowValue)
                    Text("kg")
                        .font(IndexFont.tileUnit)
                        .foregroundStyle(.secondary)
                }
                Text(absoluteDateString(entry.date))
                    .font(IndexFont.rowSecondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.source == .renpho ? "RENPHO" : entry.source == .healthkit ? "HEALTH" : "MANUAL")
                .font(IndexFont.rowSecondary)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Derived values

    private var bmiText: String {
        guard let profile, let w = weights.first?.weightKg else { return "—" }
        let value = MetricsEngine.bmi(weightKg: w, heightCm: profile.heightCm)
        return String(format: "%.1f", value)
    }

    private var bmrText: String {
        guard let profile, let w = weights.first?.weightKg else { return "—" }
        let value = MetricsEngine.bmr(
            weightKg: w, heightCm: profile.heightCm,
            age: profile.age, sex: profile.sex
        )
        return SafeFormat.int(value)
    }

    private var tdeeText: String {
        guard let profile, let w = weights.first?.weightKg else { return "—" }
        let bmr = MetricsEngine.bmr(
            weightKg: w, heightCm: profile.heightCm,
            age: profile.age, sex: profile.sex
        )
        let value = MetricsEngine.tdee(bmr: bmr, activityLevel: profile.activityLevel)
        return SafeFormat.int(value)
    }

    private var bodyFatText: String {
        if let entry = weights.first, entry.hasBodyFat {
            return String(format: "%.1f", entry.bodyFatPercent)
        }
        return "—"
    }

    private var leanMassText: String {
        if let entry = weights.first, entry.hasLeanMass {
            return formatKg(entry.leanMassKg)
        }
        if let profile, let w = weights.first?.weightKg {
            let estimated = MetricsEngine.leanBodyMass(
                weightKg: w, heightCm: profile.heightCm, sex: profile.sex
            )
            return formatKg(estimated)
        }
        return "—"
    }

    private var idealRangeText: String {
        guard let profile else { return "—" }
        let range = MetricsEngine.idealWeightRange(
            heightCm: profile.heightCm, sex: profile.sex
        )
        return "\(SafeFormat.int(range.lowerBound))–\(SafeFormat.int(range.upperBound))"
    }

    private var latestDailyMetric: DailyHealthMetrics? {
        dailyMetrics.first
    }

    // MARK: - Tile deltas
    //
    // Each delta walks the appropriate @Query result for the two
    // most-recent rows that carry the metric (via the has-Foo
    // flag), takes their difference, and packages it with the
    // metric's direction-of-good. The view renders only when the
    // change rounds to at least the display precision — no
    // "↑ 0.0" or "↓ 0" pseudo-deltas on effectively no change.
    //
    // Direction-of-good (good for the user):
    // - Body fat % → down is good (cut goal)
    // - Lean mass  → up is good (preserve muscle)
    // - HRV        → up is good (autonomic recovery)
    // - VO2 max    → up is good (aerobic fitness)
    // - Resting HR → down is good (fitness/recovery)
    //
    // Descriptive metrics (BMI, BMR, TDEE, ideal range) are
    // intentionally omitted — coloring them green/red would lie
    // about good vs. bad.

    private var bodyFatDelta: TileDelta? {
        guard let (curr, prev) = firstTwo(weights, where: { $0.hasBodyFat }) else { return nil }
        return decimalDelta(
            current: curr.bodyFatPercent,
            previous: prev.bodyFatPercent,
            unit: "%",
            goodDirection: .down
        )
    }

    private var leanMassDelta: TileDelta? {
        // Only when both current AND previous are real
        // measurements (hasLeanMass true). The MetricsEngine
        // estimation fallback in `leanMassText` is a derived
        // value with no history — comparing across estimation
        // would be noise.
        guard let (curr, prev) = firstTwo(weights, where: { $0.hasLeanMass }) else { return nil }
        return decimalDelta(
            current: curr.leanMassKg,
            previous: prev.leanMassKg,
            unit: "kg",
            goodDirection: .up
        )
    }

    private var hrvDelta: TileDelta? {
        guard let (curr, prev) = firstTwo(dailyMetrics, where: { $0.hasHRV }) else { return nil }
        return integerDelta(
            current: curr.hrvMs,
            previous: prev.hrvMs,
            unit: "ms",
            goodDirection: .up
        )
    }

    private var vo2Delta: TileDelta? {
        guard let (curr, prev) = firstTwo(dailyMetrics, where: { $0.hasVO2Max }) else { return nil }
        return decimalDelta(
            current: curr.vo2Max,
            previous: prev.vo2Max,
            unit: "",
            goodDirection: .up
        )
    }

    private var rhrDelta: TileDelta? {
        guard let (curr, prev) = firstTwo(dailyMetrics, where: { $0.hasRestingHeartRate }) else { return nil }
        return integerDelta(
            current: Double(curr.restingHeartRate),
            previous: Double(prev.restingHeartRate),
            unit: "bpm",
            goodDirection: .down
        )
    }

    /// Walk an array sorted newest-first and return the first
    /// two elements that satisfy `predicate`, or nil when fewer
    /// than two qualify. Generic so the same helper covers both
    /// `weights` and `dailyMetrics`.
    private func firstTwo<T>(_ array: [T], where predicate: (T) -> Bool) -> (current: T, previous: T)? {
        var hits: [T] = []
        for item in array {
            if predicate(item) {
                hits.append(item)
                if hits.count == 2 { return (hits[0], hits[1]) }
            }
        }
        return nil
    }

    /// One-decimal delta. Returns nil when the rounded magnitude
    /// is below 0.1 so a barely-perceptible change doesn't show
    /// a colored arrow on what's effectively no change.
    private func decimalDelta(
        current: Double,
        previous: Double,
        unit: String,
        goodDirection: GoodDirection
    ) -> TileDelta? {
        let signed = current - previous
        let rounded = (signed * 10).rounded() / 10
        let mag = abs(rounded)
        guard mag >= 0.1 else { return nil }
        return TileDelta(
            signedAmount: signed,
            formattedAbs: String(format: "%.1f", mag),
            unit: unit,
            goodDirection: goodDirection
        )
    }

    /// Integer-precision delta. Returns nil on rounded-zero.
    private func integerDelta(
        current: Double,
        previous: Double,
        unit: String,
        goodDirection: GoodDirection
    ) -> TileDelta? {
        let signed = current - previous
        let rounded = signed.rounded()
        let mag = abs(rounded)
        guard mag >= 1 else { return nil }
        return TileDelta(
            signedAmount: signed,
            formattedAbs: "\(Int(mag))",
            unit: unit,
            goodDirection: goodDirection
        )
    }

    private var hrvText: String {
        if let m = latestDailyMetric, m.hasHRV {
            return SafeFormat.int(m.hrvMs)
        }
        return "—"
    }

    private var vo2Text: String {
        if let m = latestDailyMetric, m.hasVO2Max {
            return String(format: "%.1f", m.vo2Max)
        }
        return "—"
    }

    private var rhrText: String {
        if let m = latestDailyMetric, m.hasRestingHeartRate {
            return "\(m.restingHeartRate)"
        }
        return "—"
    }

    // MARK: - Helpers

    private func computeWeightDelta() -> Double? {
        guard weights.count >= 2 else { return nil }
        return weights[0].weightKg - weights[1].weightKg
    }

    private func weightsInLastDays(_ days: Int) -> [WeightEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return weights.filter { $0.date >= cutoff }
    }

    private func dailyMetricsInLastDays(_ days: Int) -> [DailyHealthMetrics] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        return dailyMetrics.filter { $0.date >= cutoff }
    }

    private func formatKg(_ kg: Double) -> String {
        SafeFormat.decimal(kg)
    }

    private func relativeDateString(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: .now)
    }

    private func absoluteDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM · HH:mm"
        return f.string(from: d)
    }

}

// MARK: - Tile delta types

/// Which direction is "good" for a given metric. Used by
/// `TileDelta.isGood` to decide whether the change should
/// render green (good) or red (bad). Body fat / resting HR
/// are `.down`; lean mass / HRV / VO2 are `.up`. Descriptive
/// metrics (BMI, BMR, TDEE, ideal range) don't use this — they
/// don't render a delta at all.
enum GoodDirection {
    case up, down
}

/// Packaged delta payload for a Body tile. `signedAmount`
/// carries the actual change (current - previous) so the arrow
/// direction is honest about where the number moved;
/// `formattedAbs` is the pre-rounded, pre-formatted magnitude
/// string so the rendering layer doesn't redo display math.
struct TileDelta {
    let signedAmount: Double
    let formattedAbs: String
    let unit: String
    let goodDirection: GoodDirection

    /// SF Symbol picked by sign of the change. Spec: the arrow
    /// follows the NUMBER's direction, not the user-good
    /// direction — so body fat dropping shows a down arrow
    /// (which `isGood` then paints green).
    var arrowSystemName: String {
        signedAmount < 0 ? "arrow.down" : "arrow.up"
    }

    /// True when the change is good for the user given the
    /// metric's `goodDirection`. The caller maps this to
    /// semantic green / red.
    var isGood: Bool {
        switch goodDirection {
        case .up:   return signedAmount > 0
        case .down: return signedAmount < 0
        }
    }
}
