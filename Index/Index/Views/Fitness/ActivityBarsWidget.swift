import SwiftUI
import HealthKit

/// Today's Apple Activity numbers rendered as three horizontal
/// progress bars (Move outer, Exercise middle, Stand inner — same
/// data sources HKActivitySummary always exposed, just laid out as
/// bars instead of concentric rings).
///
/// Each row is `[label] [bar] [value / goal] [unit]`. The bar shape
/// matches the Steps progress bar on the right half of the Today row
/// (same height, corner radius, track-as-tinted-fill treatment) so
/// the two halves of the widget share a single shape vocabulary.
/// Overfill is communicated by the numeric pair on the right (e.g.
/// "537 / 450 kcal") — bar fill clamps at 100% width; no second
/// stacked bar, no shade shift.
///
/// Replaces the previous concentric-rings + chevrons + inset-overflow
/// stroke + tap-to-flip-stats widget. The tap interaction is gone;
/// numbers and progress are both visible at the same time.
struct ActivityBarsWidget: View {
    let summary: HKActivitySummary?
    /// Caller's overall HK auth state. When false the widget shows a
    /// "Connect Apple Watch" placeholder instead of empty bars.
    let isAuthorized: Bool
    /// Tapping the placeholder triggers HK auth via the parent.
    let onConnectTapped: () -> Void

    // Apple-convention activity colors. Hex literals matching the
    // Fitness app's signature shades — kept inline rather than
    // promoted to IndexPalette because they only apply here.
    private static let moveColor     = Color(red: 0xFA / 255, green: 0x11 / 255, blue: 0x4F / 255)
    private static let exerciseColor = Color(red: 0xA1 / 255, green: 0xF6 / 255, blue: 0x00 / 255)
    private static let standColor    = Color(red: 0x1F / 255, green: 0xDF / 255, blue: 0xE3 / 255)

    var body: some View {
        if isAuthorized {
            VStack(spacing: 12) {
                ActivityBarRow(
                    label: "Move",
                    fillColor: Self.moveColor,
                    progress: progress(.move),
                    value: valueText(.move),
                    unit: "kcal"
                )
                ActivityBarRow(
                    label: "Exercise",
                    fillColor: Self.exerciseColor,
                    progress: progress(.exercise),
                    value: valueText(.exercise),
                    unit: "min"
                )
                ActivityBarRow(
                    label: "Stand",
                    fillColor: Self.standColor,
                    progress: progress(.stand),
                    value: valueText(.stand),
                    unit: "hrs"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            placeholder
        }
    }

    // MARK: - Placeholder

    private var placeholder: some View {
        VStack(spacing: 10) {
            ActivityBarRow(label: "Move",     fillColor: Self.moveColor,     progress: 0, value: "—", unit: "kcal")
            ActivityBarRow(label: "Exercise", fillColor: Self.exerciseColor, progress: 0, value: "—", unit: "min")
            ActivityBarRow(label: "Stand",    fillColor: Self.standColor,    progress: 0, value: "—", unit: "hrs")
            Button(action: onConnectTapped) {
                Text("Connect Apple Watch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IndexPalette.Module.fitness)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(0.7)
    }

    // MARK: - Data helpers

    private enum Metric { case move, exercise, stand }

    /// Current / goal pair for a given metric. Rounds to the nearest
    /// integer because activity goals in HK are integer-valued
    /// (kcal, minutes, hours).
    private func valueText(_ metric: Metric) -> String {
        guard let s = summary else { return "—" }
        let (value, goal) = rawValueGoal(s, metric)
        return "\(Int(value.rounded())) / \(Int(goal.rounded()))"
    }

    /// 0…N progress fraction for the bar fill. Bar clamps to 1.0
    /// visually via min() at draw time — the value text past 1.0
    /// communicates overfill.
    private func progress(_ metric: Metric) -> Double {
        guard let s = summary else { return 0 }
        let (value, goal) = rawValueGoal(s, metric)
        return goal > 0 ? value / goal : 0
    }

    /// Pulls raw HKQuantity values + goals for a metric. Goal of 0
    /// can happen when the user hasn't configured the Activity app
    /// on Watch yet — the progress helper guards that case to avoid
    /// dividing by zero (returns 0, leaving the bar empty).
    private func rawValueGoal(_ s: HKActivitySummary, _ metric: Metric) -> (value: Double, goal: Double) {
        switch metric {
        case .move:
            let unit = HKUnit.kilocalorie()
            return (s.activeEnergyBurned.doubleValue(for: unit),
                    s.activeEnergyBurnedGoal.doubleValue(for: unit))
        case .exercise:
            let unit = HKUnit.minute()
            return (s.appleExerciseTime.doubleValue(for: unit),
                    s.appleExerciseTimeGoal.doubleValue(for: unit))
        case .stand:
            let unit = HKUnit.count()
            return (s.appleStandHours.doubleValue(for: unit),
                    s.appleStandHoursGoal.doubleValue(for: unit))
        }
    }
}

/// Single bar row: fixed-width label column on the left, flexible
/// bar in the middle, right-aligned value pair + unit on the
/// trailing edge. Extracted because the three Activity rows share
/// the same shape; a second consumer (heart-rate? hydration? sleep?)
/// is plausible enough that keeping the primitive reusable is cheap.
///
/// `progress` is a 0…N fraction. Bar fill width = `min(progress, 1)`
/// in geometry coordinates — overfill never visually overflows the
/// track; the value-pair text carries that signal instead.
private struct ActivityBarRow: View {
    let label: String
    let fillColor: Color
    let progress: Double
    let value: String
    let unit: String

    // Matches StepsWidget.progressBar exactly so the two halves of
    // the Today row speak the same shape vocabulary.
    private static let barHeight: CGFloat = 6
    private static let cornerRadius: CGFloat = 3
    private static let trackOpacity: Double = 0.18

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label)
                .font(IndexFont.tileLabel)
                .foregroundStyle(IndexPalette.Text.secondary)
                .frame(width: 68, alignment: .leading)
            bar
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(IndexFont.rowValue)
                    .foregroundStyle(IndexPalette.Text.primary)
                Text(unit)
                    .font(IndexFont.tileUnit)
                    .foregroundStyle(IndexPalette.Text.secondary)
            }
        }
    }

    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(fillColor.opacity(Self.trackOpacity))
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(fillColor)
                    .frame(width: geo.size.width * CGFloat(min(progress, 1)))
            }
        }
        .frame(height: Self.barHeight)
    }
}
