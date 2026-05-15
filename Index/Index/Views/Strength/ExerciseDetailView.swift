import SwiftUI
import SwiftData
import Charts

/// One exercise from the user's library. Surfaces the most recent
/// performance + a top-set-weight progress chart over the chosen range.
/// "Log new session" launches ActiveStrengthSessionView seeded with this
/// exercise.
struct ExerciseDetailView: View {
    let exercise: UserExercise

    @Environment(\.modelContext) private var context

    /// Audit H17 — bounded to last 365 days. Matches the longest
    /// progress range (1Y) the chart can render; older sessions
    /// would never appear in the chart anyway, so they don't need
    /// to be in the @Query result set. Saves transitively pulling
    /// every SetEntry ever logged.
    @Query private var sessions: [StrengthSession]

    @State private var range: ProgressRange = .threeMonths
    @State private var showActiveSession = false

    init(exercise: UserExercise) {
        self.exercise = exercise
        let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: .now) ?? .distantPast
        _sessions = Query(
            filter: #Predicate<StrengthSession> { $0.date > cutoff },
            sort: \StrengthSession.date,
            order: .reverse
        )
    }

    enum ProgressRange: String, CaseIterable, Identifiable {
        case oneMonth, threeMonths, oneYear

        var id: String { rawValue }

        var label: String {
            switch self {
            case .oneMonth:    "1M"
            case .threeMonths: "3M"
            case .oneYear:     "1Y"
            }
        }

        var daysBack: Int {
            switch self {
            case .oneMonth:    30
            case .threeMonths: 90
            case .oneYear:     365
            }
        }
    }

    private var lastPerformance: ExercisePerformance? {
        for s in sessions {
            if let p = (s.performances ?? []).first(where: {
                $0.userExerciseId == exercise.id && !($0.sets ?? []).isEmpty
            }) {
                return p
            }
        }
        return nil
    }

    private var chartData: [(date: Date, kg: Double)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.daysBack, to: .now) ?? .distantPast
        var byDay: [Date: Double] = [:]
        for s in sessions where s.date >= cutoff {
            let perfs = (s.performances ?? []).filter { $0.userExerciseId == exercise.id }
            for perf in perfs {
                let top = (perf.sets ?? []).map(\.weightKg).max() ?? 0
                if top > 0 {
                    let day = Calendar.current.startOfDay(for: s.date)
                    byDay[day] = max(byDay[day] ?? 0, top)
                }
            }
        }
        return byDay.map { (date: $0.key, kg: $0.value) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                lastSessionSection
                progressSection
                ctaButton
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showActiveSession) {
            ActiveStrengthSessionView(seedExercise: exercise)
        }
    }

    private var lastSessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last session")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            if let perf = lastPerformance {
                VStack(spacing: 0) {
                    ForEach(perf.orderedSets.indices, id: \.self) { i in
                        let set = perf.orderedSets[i]
                        HStack {
                            (Text("Set ").font(.caption)
                                + Text("\(i + 1)").font(IndexFont.monoCaption(12)))
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            (Text(formatKg(set.weightKg)).font(IndexFont.monoMedium(15))
                                + Text(" kg × ").font(.body)
                                + Text("\(set.reps)").font(IndexFont.monoMedium(15)))
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
            } else {
                Text("No history yet. Log your first set below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(IndexPalette.Surface.card)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(ProgressRange.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            chart
        }
    }

    @ViewBuilder
    private var chart: some View {
        let data = chartData
        if data.count >= 2 {
            Chart(data, id: \.date) { pt in
                LineMark(
                    x: .value("Date", pt.date),
                    y: .value("kg", pt.kg)
                )
                .foregroundStyle(.tint)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Date", pt.date),
                    y: .value("kg", pt.kg)
                )
                .foregroundStyle(.tint)
                .symbolSize(28)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 200)
        } else {
            Text("Log more sessions to see progression.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(IndexPalette.Surface.card)
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    private var ctaButton: some View {
        Button {
            showActiveSession = true
        } label: {
            Text("Log new session")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func formatKg(_ kg: Double) -> String {
        SafeFormat.decimal(kg)
    }
}
