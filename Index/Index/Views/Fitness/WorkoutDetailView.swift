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
            Text(absoluteDateString(session.date))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatDuration(session.durationMinutes))
                    .font(IndexFont.monoHero(44))
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
                statTile(label: "Energy", value: SafeFormat.int(session.kcalBurned), unit: "kcal")
            }
            if session.hasDistance {
                statTile(label: "Distance", value: SafeFormat.decimal(session.distanceKm), unit: "km")
            }
            if session.type == .swimming, let avgSwolf = swimDetail?.avgSWOLF {
                statTile(label: "Avg SWOLF", value: SafeFormat.int(avgSwolf), unit: nil, valueColor: Self.swolfTeal)
            }
            if session.type == .swimming, let pool = swimDetail?.poolLengthMeters {
                // Neutral value color (default Color.primary) — teal stays
                // exclusive to SWOLF as the swim-efficiency metric.
                statTile(label: "Pool Length", value: "\(Int(pool.rounded()))", unit: "m")
            }
        }
    }

    private func statTile(
        label: String,
        value: String,
        unit: String?,
        valueColor: Color? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(IndexFont.monoTile(20))
                    .foregroundStyle(valueColor ?? Color.primary)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            Text("Heart Rate")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text("Loading samples…")
                    .font(.caption)
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
            Text("Heart Rate")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
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
            // "153 BPM AVG" — number mono, label sans.
            (Text("\(Int(avg.rounded()))").font(IndexFont.monoCaption(12))
                + Text(" BPM AVG").font(.caption))
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
            Text("Route")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
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
            Text("Notes")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
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
