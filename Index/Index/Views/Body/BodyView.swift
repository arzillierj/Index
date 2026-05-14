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
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert = false

    private var profile: Profile? { profileService.activeProfile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                insightSection
                heroWeight
                trendChart
                metricsSection
                vitalsSection
                recentEntriesSection
            }
            .padding()
        }
        .navigationTitle("Body")
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
            // P4.14 replaces this placeholder with the real LogWeightSheet.
            VStack(spacing: 12) {
                Text("Log weight").font(.title2.weight(.semibold))
                Text("Coming in P4.14.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .presentationDetents([.medium])
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
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

    // MARK: - Hero weight

    private var heroWeight: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest weight")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let latest = weights.first {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formatKg(latest.weightKg))
                        .font(.system(size: 56, weight: .semibold, design: .monospaced))
                    Text("kg")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Text(relativeDateString(latest.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let delta = computeWeightDelta() {
                        deltaLabel(delta)
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 56, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text("Tap Log to add your first entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deltaLabel(_ kgDelta: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: kgDelta < 0 ? "arrow.down" : "arrow.up")
                .font(.caption2)
            Text("\(formatKg(abs(kgDelta))) kg")
                .font(.caption.monospacedDigit())
        }
        .foregroundStyle(.secondary)
    }

    // MARK: - Trend chart

    @ViewBuilder
    private var trendChart: some View {
        let series = weightsInLastDays(30).sorted { $0.date < $1.date }
        if series.count >= 2 {
            Chart {
                ForEach(series, id: \.persistentModelID) { entry in
                    AreaMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [.accentColor.opacity(0.25), .accentColor.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .interpolationMethod(.monotone)

                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weightKg)
                    )
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                }
            }
            .frame(height: 180)
        } else {
            Text("Log more weights to see your trend.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
        }
    }

    // MARK: - Metrics grid

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Composition")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                tile(label: "BMI", value: bmiText, unit: nil) { showBMIInfo() }
                tile(label: "BMR", value: bmrText, unit: "kcal") { showBMRInfo() }
                tile(label: "TDEE", value: tdeeText, unit: "kcal") { showTDEEInfo() }
                tile(label: "Body fat", value: bodyFatText, unit: bodyFatText == "—" ? nil : "%") { showBodyFatInfo() }
                tile(label: "Lean mass", value: leanMassText, unit: leanMassText == "—" ? nil : "kg") { showLeanMassInfo() }
                tile(label: "Ideal range", value: idealRangeText, unit: "kg") { showIdealRangeInfo() }
            }
        }
    }

    private var vitalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vitals")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                tile(label: "HRV", value: hrvText, unit: hrvText == "—" ? nil : "ms") { showHRVInfo() }
                tile(label: "VO2 max", value: vo2Text, unit: nil) { showVO2Info() }
                tile(label: "Resting HR", value: rhrText, unit: rhrText == "—" ? nil : "bpm") { showRHRInfo() }
            }
        }
    }

    private func tile(
        label: String,
        value: String,
        unit: String?,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.primary)
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
            .background(Color(.secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent entries

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent entries")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Spacer()
                // P4.16 wires this NavigationLink to the full history list.
                Text("See all")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if weights.isEmpty {
                Text("No entries yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    ForEach(weights.prefix(5)) { entry in
                        // P4.15 wires this row to WeightEntryDetailSheet.
                        recentEntryRow(entry: entry)
                        if entry.persistentModelID != weights.prefix(5).last?.persistentModelID {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private func recentEntryRow(entry: WeightEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatKg(entry.weightKg)) kg")
                    .font(.body.monospacedDigit())
                Text(absoluteDateString(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.source == .renpho ? "RENPHO" : entry.source == .healthkit ? "HEALTH" : "MANUAL")
                .font(.caption2.monospaced())
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
        return "\(Int(value.rounded()))"
    }

    private var tdeeText: String {
        guard let profile, let w = weights.first?.weightKg else { return "—" }
        let bmr = MetricsEngine.bmr(
            weightKg: w, heightCm: profile.heightCm,
            age: profile.age, sex: profile.sex
        )
        let value = MetricsEngine.tdee(bmr: bmr, activityLevel: profile.activityLevel)
        return "\(Int(value.rounded()))"
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
        return "\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded()))"
    }

    private var latestDailyMetric: DailyHealthMetrics? {
        dailyMetrics.first
    }

    private var hrvText: String {
        if let m = latestDailyMetric, m.hasHRV {
            return "\(Int(m.hrvMs.rounded()))"
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
        kg == floor(kg) ? "\(Int(kg))" : String(format: "%.1f", kg)
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

    // MARK: - Metric explanations (formula citations)

    private func explain(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func showBMIInfo() {
        explain("BMI", "Body Mass Index = weight (kg) ÷ height² (m²). WHO 1995 categories.")
    }

    private func showBMRInfo() {
        explain("BMR — Mifflin-St Jeor",
                "Basal Metabolic Rate.\nMale: 10W + 6.25H − 5A + 5\nFemale: 10W + 6.25H − 5A − 161\nMifflin et al., Am J Clin Nutr 51(2):241–247, 1990.")
    }

    private func showTDEEInfo() {
        explain("TDEE",
                "Total Daily Energy Expenditure = BMR × Harris-Benedict activity multiplier. McArdle 2010.")
    }

    private func showBodyFatInfo() {
        if let entry = weights.first, entry.hasBodyFat {
            let src = entry.source == .renpho
                ? "From RENPHO via Apple Health."
                : "From Apple Health."
            explain("Body fat %", src)
        } else {
            explain("Body fat %", "No reading yet. RENPHO writes body fat to Apple Health on each weigh-in.")
        }
    }

    private func showLeanMassInfo() {
        if let entry = weights.first, entry.hasLeanMass {
            let src = entry.source == .renpho
                ? "From RENPHO via Apple Health."
                : "From Apple Health."
            explain("Lean mass", src)
        } else {
            explain("Lean mass — Boer 1984",
                    "Male: 0.407W + 0.267H − 19.2\nFemale: 0.252W + 0.473H − 48.3\nBoer P, J Appl Physiol 57(4):1186–1190, 1984. Shown as an estimate until a scale reports a measured value.")
        }
    }

    private func showIdealRangeInfo() {
        explain("Ideal range — Devine 1974",
                "50 + 2.3 × (height − 60 in) for men; 45.5 + 2.3 × (height − 60 in) for women. ±10% range. Devine BJ, Drug Intell Clin Pharm 8:650–655, 1974.")
    }

    private func showHRVInfo() {
        explain("HRV (SDNN)",
                "Standard deviation of beat-to-beat intervals during overnight sleep. From Apple Health.")
    }

    private func showVO2Info() {
        explain("VO2 max",
                "Cardio-fitness estimate in mL/(kg·min). From Apple Health.")
    }

    private func showRHRInfo() {
        explain("Resting heart rate",
                "Average resting BPM measured by Apple Watch. From Apple Health.")
    }
}
