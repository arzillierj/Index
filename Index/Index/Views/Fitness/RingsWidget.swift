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
/// Renders directly on the page background — no card chrome. Tap the
/// rings to flip the widget to a stats face (Move / Exercise / Stand
/// current-over-goal rows in their ring colors); tap again to flip
/// back. The flip is a Y-axis `rotation3DEffect` with synchronized
/// face opacity so the cross-fade happens at the edge-on midpoint.
///
/// Data flows in from FitnessMainView so the parent's `.refreshable`
/// can refetch and pass the new summary down with one hop. The
/// widget owns the `displayProgress` triple it animates toward when
/// the summary changes.
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
    @State private var showingStats: Bool = false

    var body: some View {
        Group {
            if isAuthorized {
                flippableFaces
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        // No card background — both faces render directly on the
        // page alabaster. Removing the .background + .clipShape that
        // used to wrap the content.
        .onAppear { animateIn() }
        .onChange(of: summary) { _, _ in animateIn() }
    }

    // MARK: - Flip container
    //
    // ZStack with two faces. The outer rotation3DEffect carries both
    // faces 180° together; the stats face is internally pre-rotated
    // 180° so when the outer is at 180° the stats text reads
    // unmirrored. Face opacity flips with the same animation, so
    // both are at ~50% at the edge-on midpoint of the flip — fine
    // because both are nearly invisible at that perspective anyway.

    private var flippableFaces: some View {
        ZStack {
            ringsFace
                .opacity(showingStats ? 0 : 1)
            statsFace
                .opacity(showingStats ? 1 : 0)
                .rotation3DEffect(
                    .degrees(180),
                    axis: (x: 0, y: 1, z: 0)
                )
        }
        .rotation3DEffect(
            .degrees(showingStats ? 180 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
        .animation(.easeInOut(duration: 0.3), value: showingStats)
        .contentShape(Rectangle())
        .onTapGesture { showingStats.toggle() }
    }

    // MARK: - Rings face

    private var ringsFace: some View {
        VStack(spacing: 10) {
            ringsStack
            Text("Move · Exercise · Stand")
                .font(.caption)
                .foregroundStyle(IndexPalette.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var ringsStack: some View {
        ZStack {
            ring(progress: displayMove,     color: Self.moveColor,     diameter: Self.outerDiameter, arrow: .single)
            ring(progress: displayExercise, color: Self.exerciseColor, diameter: Self.middleDiameter, arrow: .double)
            ring(progress: displayStand,    color: Self.standColor,    diameter: Self.innerDiameter, arrow: .up)
        }
        .frame(width: Self.outerDiameter, height: Self.outerDiameter)
    }

    /// Single ring = main arc + optional inset overflow arc + the
    /// Apple-convention chevron at the 12 o'clock position.
    ///
    /// Main arc trims to `min(progress, 1)` at full width and hue.
    /// When progress > 1, a second concentric arc draws the overage
    /// INSIDE the main ring (smaller diameter, same hue, same
    /// opacity) — Apple Activity's "past the goal" signature. The
    /// arc length is (progress - 1), clamped to 1.0 so e.g. 300%
    /// caps the inset ring at one full revolution rather than
    /// stacking laps invisibly.
    ///
    /// The previous "faded background loop + brighter overage on
    /// top" treatment is gone — that read as an incomplete
    /// background layer rather than overachievement.
    ///
    /// The chevron sits ON the main stroke (Y offset = -radius) and
    /// uses the brighter ring color for legibility against the
    /// saturated arc.
    @ViewBuilder
    private func ring(progress: Double, color: Color, diameter: CGFloat, arrow: ArrowGlyph) -> some View {
        ZStack {
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)
            if progress > 1 {
                // Inset overflow ring. Diameter reduced by ringWidth+4
                // on each side (≈ ringWidth+4 radial inset) so the
                // overflow band sits clearly inside the main ring's
                // hollow with a small visible gap — same hue, no
                // opacity reduction, no width change.
                let insetDiameter = diameter - (Self.ringWidth * 2 + 4)
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress - 1, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: insetDiameter, height: insetDiameter)
            }
            Image(systemName: arrow.systemName)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(brighter(color))
                .offset(y: -diameter / 2)
        }
        .frame(width: diameter, height: diameter)
    }

    /// Mirrors Apple's per-ring arrow convention.
    /// Move (outer)     → single chevron pointing along the clockwise sweep
    /// Exercise (middle)→ double chevron, same direction
    /// Stand (inner)    → up chevron, the Fitness app's stand glyph
    private enum ArrowGlyph {
        case single, double, up

        var systemName: String {
            switch self {
            case .single: "chevron.right"
            case .double: "chevron.right.2"
            case .up:     "chevron.up"
            }
        }
    }

    /// Mixes the base ring color with white to brighten the
    /// overachievement loop AND the chevron glyphs. SwiftUI doesn't
    /// expose a built-in "blend with white" so we go through UIColor.
    private func brighter(_ c: Color) -> Color {
        Color(uiColor: UIColor(c).withAlphaComponent(1).blended(withFraction: 0.35, of: .white))
    }

    // MARK: - Stats face

    private var statsFace: some View {
        // Reserve the same height as the rings face so the parent
        // ScrollView doesn't reflow mid-flip. Outer frame matches
        // ringsStack's diameter plus caption baseline.
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                statRow(
                    label: "Move",
                    value: moveValueText,
                    unit: "kcal",
                    color: Self.moveColor
                )
                statRow(
                    label: "Exercise",
                    value: exerciseValueText,
                    unit: "min",
                    color: Self.exerciseColor
                )
                statRow(
                    label: "Stand",
                    value: standValueText,
                    unit: "hrs",
                    color: Self.standColor
                )
            }
            .frame(width: Self.outerDiameter + 20)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(width: Self.outerDiameter, height: Self.outerDiameter + 22)
    }

    private func statRow(label: String, value: String, unit: String, color: Color) -> some View {
        // Label left in primary, "current / goal unit" right in the
        // ring color. heroCaption carries monospacedDigit so the
        // digit columns align across the three rows.
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(IndexFont.heroCaption)
                .foregroundStyle(IndexPalette.Text.primary)
            Spacer(minLength: 4)
            Text("\(value) \(unit)")
                .font(IndexFont.heroCaption)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Placeholder

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

    // MARK: - Stats-face text (read directly from summary; no animation)

    // The text helpers return just the "current / goal" number pair
    // — the unit string is appended by statRow's sans-font segment.

    private var moveValueText: String {
        guard let s = summary else { return "—" }
        let value = Int(s.activeEnergyBurned.doubleValue(for: .kilocalorie()).rounded())
        let goal = Int(s.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()).rounded())
        return "\(value) / \(goal)"
    }

    private var exerciseValueText: String {
        guard let s = summary else { return "—" }
        let value = Int(s.appleExerciseTime.doubleValue(for: .minute()).rounded())
        let goal = Int(s.appleExerciseTimeGoal.doubleValue(for: .minute()).rounded())
        return "\(value) / \(goal)"
    }

    private var standValueText: String {
        guard let s = summary else { return "—" }
        let value = Int(s.appleStandHours.doubleValue(for: .count()).rounded())
        let goal = Int(s.appleStandHoursGoal.doubleValue(for: .count()).rounded())
        return "\(value) / \(goal)"
    }
}

// MARK: - UIColor brighten helper

private extension UIColor {
    /// Linearly mixes self toward the given color by `fraction`
    /// (0…1). Used by the rings widget's overachievement loop and
    /// the 12 o'clock chevrons.
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
