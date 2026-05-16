import SwiftUI
import SwiftData
import Charts

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
    @Environment(HealthKitService.self) private var hkService

    @State private var showDeleteConfirm = false

    // Swim-only enrichment loaded from HK on appear. Nil for non-swim
    // workouts, manual entries, and any swim that HK can't find by UUID.
    @State private var swimDetail: SwimDetailData? = nil
    @State private var isLoadingSwim = false
    @State private var showAutoSets = false

    // Data-viz colors come from IndexPalette so a future hex swap is one
    // edit; heart-rate red and SWOLF teal are stable semantic mappings.
    private static let hrRed     = IndexPalette.Data.heartRate
    private static let swolfTeal = IndexPalette.Data.efficiency

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                if session.type == .swimming {
                    swimHeartRateSection
                }
                statsGrid
                if session.type == .swimming, let detail = swimDetail, !detail.sets.isEmpty {
                    autoSetsRow
                }
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
        // Top safe-area inset (matches the main-tab views) — explicit
        // surface color so iOS 26 Liquid Glass doesn't keep the bar
        // translucent. Without this, the duration hero ("2h 53m") slid
        // under the status bar on scroll. See BodyView for detail.
        .toolbarBackground(IndexPalette.Surface.background, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
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
        .task {
            await loadSwimDetailIfNeeded()
        }
        .sheet(isPresented: $showAutoSets) {
            if let detail = swimDetail {
                SwimAutoSetsSheet(sets: detail.sets, lengths: detail.lengths)
            }
        }
    }

    // MARK: - Swim load

    private var canFetchSwimDetail: Bool {
        session.type == .swimming
            && session.source == .healthkit
            && (session.hkWorkoutUUID?.isEmpty == false)
    }

    private func loadSwimDetailIfNeeded() async {
        guard canFetchSwimDetail, swimDetail == nil, !isLoadingSwim else { return }
        guard let uuid = session.hkWorkoutUUID, !uuid.isEmpty else { return }
        isLoadingSwim = true
        swimDetail = await hkService.fetchSwimDetail(forWorkoutUUID: uuid)
        isLoadingSwim = false
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section 6 layout-hardening: the "Apple Health" /
            // "Manual" attribution sits on the date line, not as a
            // trailing chip pressed against the duration hero. The
            // hero now has the whole row to itself (and is free to
            // scale down via .minimumScaleFactor if the duration
            // string is long, e.g. "2h 53m"); attribution reads as
            // a quiet sibling of the date.
            HStack(spacing: 8) {
                Text(absoluteDateString(session.date))
                    .font(IndexFont.heroCaption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .font(IndexFont.heroCaption)
                    .foregroundStyle(.tertiary)
                sourceBadge
                Spacer(minLength: 0)
            }
            Text(formatDuration(session.durationMinutes))
                .font(IndexFont.hero)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if session.hasIntensity {
                Text("Intensity \(session.intensity) / 5")
                    .font(IndexFont.heroCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceBadge: some View {
        Text(session.source == .healthkit ? "Apple Health" : "Manual")
            .font(IndexFont.heroCaption)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Stats

    /// Stat tiles available for this session. Each `statCell` is a
    /// rendered tile view, sequenced in display order. Order
    /// matters — pairs walk left-to-right, top-to-bottom; an odd
    /// trailing cell spans both columns so we never leave a half-
    /// width orphan card (Section 5 layout-hardening: Cycling's
    /// 2+1 layout used to drop the third tile alone on the bottom
    /// row).
    private var statCells: [AnyView] {
        var cells: [AnyView] = []
        if session.hasHeartRate {
            cells.append(AnyView(statTile(label: "Avg HR", value: "\(session.avgHeartRate)", unit: "bpm")))
        }
        if session.hasMaxHeartRate {
            cells.append(AnyView(statTile(label: "Max HR", value: "\(session.maxHeartRate)", unit: "bpm")))
        }
        if session.hasKcal {
            cells.append(AnyView(statTile(label: "Energy", value: SafeFormat.int(session.kcalBurned), unit: "kcal")))
        }
        if session.hasDistance {
            cells.append(AnyView(statTile(label: "Distance", value: SafeFormat.decimal(session.distanceKm), unit: "km")))
        }
        if session.type == .swimming, let avgSwolf = swimDetail?.avgSWOLF {
            cells.append(AnyView(statTile(label: "Avg SWOLF", value: SafeFormat.int(avgSwolf), unit: nil, valueColor: Self.swolfTeal)))
        }
        if session.type == .swimming, let pool = swimDetail?.poolLengthMeters {
            // Neutral value color (default Color.primary) — teal stays
            // exclusive to SWOLF as the swim-efficiency metric.
            cells.append(AnyView(statTile(label: "Pool Length", value: "\(Int(pool.rounded()))", unit: "m")))
        }
        return cells
    }

    @ViewBuilder
    private var statsGrid: some View {
        let cells = statCells
        let pairCount = cells.count / 2
        let hasOddTrailing = cells.count % 2 == 1
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<pairCount, id: \.self) { row in
                GridRow {
                    cells[row * 2]
                    cells[row * 2 + 1]
                }
            }
            if hasOddTrailing {
                GridRow {
                    cells[cells.count - 1]
                        .gridCellColumns(2)
                }
            }
        }
    }

    /// Section 4 layout-hardening: same clip-proof pattern as
    /// BodyView's `tile(label:value:unit:)`. The numeral scales
    /// down via `minimumScaleFactor(0.6)`; the unit has
    /// `layoutPriority(1)` so when space is tight the numeral
    /// shrinks instead of the unit ("bpm" / "kcal" / "km")
    /// clipping at the trailing edge.
    private func statTile(
        label: String,
        value: String,
        unit: String?,
        valueColor: Color? = nil
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
                    .foregroundStyle(valueColor ?? Color.primary)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Swim heart rate section (above stat grid, swim-only)

    @ViewBuilder
    private var swimHeartRateSection: some View {
        if session.source == .healthkit {
            if isLoadingSwim {
                heartRateLoading
            } else if let samples = swimDetail?.hrSamples, !samples.isEmpty {
                heartRateChart(samples: samples)
            }
            // else: no samples → hide entirely (per spec)
        }
    }

    private var heartRateLoading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HEART RATE")
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading samples…")
                    .font(IndexFont.rowSecondary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func heartRateChart(samples: [SwimHRSample]) -> some View {
        let bpms     = samples.map(\.bpm)
        let minBPM   = bpms.min() ?? 0
        let maxBPM   = bpms.max() ?? 0
        // Pad ±10 BPM, clamp lower to 0 so HR can't go negative.
        let yLow     = max(0, (minBPM - 10).rounded(.down))
        let yHigh    = (maxBPM + 10).rounded(.up)
        let avg      = bpms.isEmpty ? 0 : bpms.reduce(0, +) / Double(bpms.count)
        let start    = samples.first?.date ?? .now
        let end      = samples.last?.date  ?? .now
        let mid      = start.addingTimeInterval(end.timeIntervalSince(start) / 2)

        return VStack(alignment: .leading, spacing: 8) {
            Text("HEART RATE")
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            Chart {
                ForEach(samples) { sample in
                    LineMark(
                        x: .value("Time", sample.date),
                        y: .value("BPM",  sample.bpm)
                    )
                    .foregroundStyle(Self.hrRed)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartYScale(domain: yLow...yHigh)
            .chartXAxis {
                AxisMarks(values: [start, mid, end]) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 160)
            // Single Text — `.monospacedDigit()` on rowSecondary
            // aligns the BPM digits tabularly without a font swap.
            Text("\(Int(avg.rounded())) BPM AVG")
                .font(IndexFont.rowSecondary)
                .foregroundStyle(Self.hrRed)
                .tracking(0.6)
        }
    }

    // MARK: - Auto Sets row (swim-only, opens detail sheet)

    private var autoSetsRow: some View {
        Button {
            showAutoSets = true
        } label: {
            HStack {
                Text("Auto Sets")
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Route placeholder (cycling only)

    private var routePlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ROUTE")
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            ZStack {
                IndexPalette.Surface.card
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
            Text("NOTES")
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            Text(displayNotes)
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

    // MARK: - Formatters

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
}
