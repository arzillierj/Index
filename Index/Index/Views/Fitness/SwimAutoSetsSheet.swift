import SwiftUI

/// Bottom sheet for an HK swim workout: per-set summary on top, per-length
/// breakdown below. Read-only — the spec explicitly excludes any
/// granularity toggle, splits view, or annotation. 25m pool only.
///
/// Both lists scroll together in one continuous ScrollView. Set cards are
/// the primary surface (more visual weight); the length-by-length grid is
/// a denser secondary view that shows which lengths slowed down or where
/// rest was longer.
struct SwimAutoSetsSheet: View {
    let sets: [SwimSet]
    let lengths: [SwimLength]

    @Environment(\.dismiss) private var dismiss

    // Data-viz colors come from IndexPalette so a future hex swap is one
    // edit. Yellow rest reuses Data.time at reduced opacity for the
    // "swim active vs. rest" pairing.
    private static let blueDistance = IndexPalette.Data.distance
    private static let yellowSwim   = IndexPalette.Data.time
    private static let yellowRest   = IndexPalette.Data.time.opacity(0.55)
    private static let teal         = IndexPalette.Data.efficiency

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    perSetSection
                    perLengthSection
                }
                .padding()
            }
            .navigationTitle("Auto Sets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(IndexPalette.Text.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Per-set summary (top, primary)

    private var perSetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sets")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            VStack(spacing: 10) {
                ForEach(sets) { set in
                    setCard(set)
                }
            }
        }
    }

    private func setCard(_ set: SwimSet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Set \(set.index)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
                Text(set.stroke.label)
                    .font(.headline)
                Spacer()
                Text("\(Int(set.distanceMeters.rounded()))m")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Self.blueDistance)
            }

            HStack(alignment: .top, spacing: 10) {
                statColumn(label: "Swim", value: formatMMSS(set.swimDuration), color: Self.yellowSwim)
                statColumn(label: "Rest", value: formatMMSS(set.restDuration), color: Self.yellowRest)
                if let swolf = set.avgSWOLF {
                    statColumn(label: "SWOLF", value: SafeFormat.int(swolf), color: Self.teal)
                }
                statColumn(
                    label: "Pace /100m",
                    value: formatPace(set.pacePer100m, hr: set.avgHR),
                    color: .primary
                )
            }
        }
        .padding(14)
        .background(IndexPalette.Surface.card)
        .clipShape(.rect(cornerRadius: 14))
    }

    private func statColumn(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Per-length breakdown (below, secondary)

    private var perLengthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lengths")
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tracking(0.8)
            VStack(spacing: 0) {
                ForEach(Array(lengths.enumerated()), id: \.element.id) { idx, len in
                    lengthRow(len)
                    if idx < lengths.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    private func lengthRow(_ length: SwimLength) -> some View {
        HStack(spacing: 8) {
            Text("\(length.index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(length.stroke.label)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text(formatMMSS(length.duration))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Self.yellowSwim)
                .frame(width: 64, alignment: .trailing)
            Text(length.swolf.map(String.init) ?? "—")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Self.teal)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Formatters

    private func formatMMSS(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    /// "M'SS\"/HR" — e.g. 3'47"/115. HR portion omitted when avgHR is
    /// missing (no HR samples in the set's window).
    private func formatPace(_ pace: TimeInterval, hr: Double?) -> String {
        guard pace > 0, pace.isFinite else { return "—" }
        let total = max(0, Int(pace.rounded()))
        let m = total / 60
        let s = total % 60
        let p = String(format: "%d'%02d\"", m, s)
        if let hr, hr > 0 {
            return "\(p)/\(Int(hr.rounded()))"
        }
        return p
    }
}
