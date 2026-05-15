import SwiftUI

/// Today's step count + thin progress bar against a hardcoded
/// 10,000-step goal. Hero number uses Swiss locale apostrophe
/// thousands separator ("8'247"). Overachievement: bar saturates at
/// 100% but the text shows the actual count, no clamp.
struct StepsWidget: View {
    let stepsToday: Int?
    /// Mirrors RingsWidget's auth gate so the two widgets show the
    /// same placeholder treatment when HK isn't connected.
    let isAuthorized: Bool
    let onConnectTapped: () -> Void

    /// Hardcoded for v1 per spec — Settings customization deferred.
    static let goal: Int = 10_000

    var body: some View {
        // Spacer-sandwich so the content centers vertically when the
        // parent HStack gives this column more height than its
        // intrinsic stack (rings card is the height driver). With
        // both Spacers at minLength 0 they collapse to nothing when
        // height is tight, leaving the original top-aligned layout
        // on narrow widgets.
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text("Steps")
                .font(.caption.smallCaps())
                .foregroundStyle(IndexPalette.Text.secondary)
                .tracking(0.8)
            if isAuthorized {
                hero
                caption
                progressBar
            } else {
                placeholder
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // No card background — renders directly on the page
        // alabaster, in line with the rings widget's flat treatment.
    }

    private var hero: some View {
        Text(Self.formatSwiss(stepsToday ?? 0))
            .font(IndexFont.monoHero(30))
            .foregroundStyle(IndexPalette.Text.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var caption: some View {
        Text("of \(Self.formatSwiss(Self.goal)) steps")
            .font(.caption)
            .foregroundStyle(IndexPalette.Text.secondary)
    }

    /// Thin pill — full-width track with a colored fill that clamps
    /// to the goal even when the actual count exceeds it. The track
    /// is a low-alpha version of the same color so the unfilled
    /// portion stays in-family rather than reading as a neutral
    /// gray bar across a tinted card.
    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(IndexPalette.Module.fitness.opacity(0.18))
                RoundedRectangle(cornerRadius: 3)
                    .fill(IndexPalette.Module.fitness)
                    .frame(width: geo.size.width * CGFloat(progressFraction))
            }
        }
        .frame(height: 6)
        .padding(.top, 4)
    }

    private var progressFraction: Double {
        guard let steps = stepsToday, steps > 0 else { return 0 }
        return min(1.0, Double(steps) / Double(Self.goal))
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("—")
                .font(IndexFont.monoHero(30))
                .foregroundStyle(IndexPalette.Text.tertiary)
            Button(action: onConnectTapped) {
                Text("Allow Health access")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IndexPalette.Module.fitness)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Swiss locale formatter (apostrophe thousands separator)
    //
    // de_CH / fr_CH / it_CH all use apostrophe-grouped thousands per
    // Bundesamt für Statistik convention. Locale-bound NumberFormatter
    // does it correctly under most iOS versions, but rolling our own
    // is two cheap lines and avoids the dependency on locale
    // catalog completeness.

    static func formatSwiss(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.insert("'", at: out.startIndex) }
            out.insert(ch, at: out.startIndex)
        }
        return n < 0 ? "-\(out)" : out
    }
}
