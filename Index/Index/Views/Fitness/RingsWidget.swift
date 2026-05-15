import SwiftUI
import HealthKit
import UIKit

/// Today's Apple Activity rings rendered as three concentric arcs
/// (Move outer, Exercise middle, Stand inner — same color + position
/// convention as the Fitness app). Animates from 0 to current
/// progress on appear / on data change. Overachievement (progress >
/// 1.0) draws a second arc in a brighter shade on top of the base
/// ring for the partial-loop visual signature.
///
/// Data flows in from FitnessMainView so the parent's
/// `.refreshable` can refetch and pass the new summary down with one
/// hop. The widget owns the `displayProgress` triple it animates
/// toward when the summary changes.
struct RingsWidget: View {
    let summary: HKActivitySummary?
    /// Caller's overall HK auth state. When false the widget shows
    /// a "Connect Apple Watch" placeholder instead of empty rings.
    let isAuthorized: Bool
    /// Tapping the placeholder triggers HK auth via the parent.
    let onConnectTapped: () -> Void

    // Apple-convention ring colors. Hex literals matching the Fitness
    // app's signature shades — kept inline rather than promoted to
    // IndexPalette because they only apply here.
    private static let moveColor     = Color(red: 0xFA / 255, green: 0x11 / 255, blue: 0x4F / 255)
    private static let exerciseColor = Color(red: 0xA1 / 255, green: 0xF6 / 255, blue: 0x00 / 255)
    private static let standColor    = Color(red: 0x1F / 255, green: 0xDF / 255, blue: 0xE3 / 255)

    private static let ringWidth: CGFloat = 12
    private static let outerDiameter: CGFloat = 110
    private static let middleDiameter: CGFloat = 80
    private static let innerDiameter: CGFloat = 50

    @State private var displayMove: Double = 0
    @State private var displayExercise: Double = 0
    @State private var displayStand: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            if isAuthorized {
                ringsStack
                Text("Move · Exercise · Stand")
                    .font(.caption)
                    .foregroundStyle(IndexPalette.Text.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 12))
        .onAppear { animateIn() }
        .onChange(of: summary) { _, _ in animateIn() }
    }

    private var ringsStack: some View {
        ZStack {
            ring(progress: displayMove,     color: Self.moveColor,     diameter: Self.outerDiameter)
            ring(progress: displayExercise, color: Self.exerciseColor, diameter: Self.middleDiameter)
            ring(progress: displayStand,    color: Self.standColor,    diameter: Self.innerDiameter)
        }
        .frame(width: Self.outerDiameter, height: Self.outerDiameter)
    }

    /// Single ring = faded background loop + foreground arc(s).
    /// The base arc trims to `min(progress, 1)`; if progress > 1 a
    /// second arc draws the overage in a brighter shade on top of the
    /// base ring (Apple's overachievement signature).
    @ViewBuilder
    private func ring(progress: Double, color: Color, diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: CGFloat(progress.truncatingRemainder(dividingBy: 1)))
                    .stroke(brighter(color), style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// Mixes the base ring color with white to brighten the
    /// overachievement loop. SwiftUI doesn't expose a built-in
    /// "blend with white" so we go through UIColor.
    private func brighter(_ c: Color) -> Color {
        Color(uiColor: UIColor(c).withAlphaComponent(1).blended(withFraction: 0.35, of: .white))
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            ringsStack
                .opacity(0.35)
            Button(action: onConnectTapped) {
                Text("Connect Apple Watch")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IndexPalette.Module.fitness)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data → progress

    private func animateIn() {
        let goals = computeProgress()
        // Reset to 0 first so the animation runs every time data
        // changes, not just on first appear.
        displayMove = 0
        displayExercise = 0
        displayStand = 0
        withAnimation(.easeOut(duration: 0.6)) {
            displayMove = goals.move
            displayExercise = goals.exercise
            displayStand = goals.stand
        }
    }

    /// Returns (move, exercise, stand) as 0…N where 1.0 = goal met.
    /// Treats absent/zero goals as nil-progress (0) so the ring
    /// renders empty rather than dividing-by-zero. Goal of 0 happens
    /// when the user hasn't configured the Activity app on Watch yet.
    private func computeProgress() -> (move: Double, exercise: Double, stand: Double) {
        guard let s = summary else { return (0, 0, 0) }
        let kcalUnit = HKUnit.kilocalorie()
        let minUnit  = HKUnit.minute()
        let countUnit = HKUnit.count()

        let moveGoal     = s.activeEnergyBurnedGoal.doubleValue(for: kcalUnit)
        let moveValue    = s.activeEnergyBurned.doubleValue(for: kcalUnit)
        let exerciseGoal = s.appleExerciseTimeGoal.doubleValue(for: minUnit)
        let exerciseVal  = s.appleExerciseTime.doubleValue(for: minUnit)
        let standGoal    = s.appleStandHoursGoal.doubleValue(for: countUnit)
        let standVal     = s.appleStandHours.doubleValue(for: countUnit)

        return (
            move:     moveGoal > 0     ? moveValue / moveGoal      : 0,
            exercise: exerciseGoal > 0 ? exerciseVal / exerciseGoal : 0,
            stand:    standGoal > 0    ? standVal / standGoal       : 0
        )
    }
}

// MARK: - UIColor brighten helper

private extension UIColor {
    /// Linearly mixes self toward the given color by `fraction`
    /// (0…1). Used by the rings widget's overachievement loop.
    func blended(withFraction fraction: CGFloat, of other: UIColor) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = max(0, min(1, fraction))
        return UIColor(
            red:   r1 + (r2 - r1) * f,
            green: g1 + (g2 - g1) * f,
            blue:  b1 + (b2 - b1) * f,
            alpha: a1 + (a2 - a1) * f
        )
    }
}
