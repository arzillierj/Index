import SwiftUI
import SwiftData

/// Full chronological list of every WeightEntry the user hasn't soft-deleted.
/// Swipe-to-delete flips `deletedFromIndex = true` so HK re-import dedup
/// still sees the row and treats it as a tombstone (v0 contract).
struct WeightHistoryView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<WeightEntry> { !$0.deletedFromIndex },
        sort: \WeightEntry.date,
        order: .reverse
    )
    private var weights: [WeightEntry]

    @State private var selectedEntry: WeightEntry?

    var body: some View {
        Group {
            if weights.isEmpty {
                ContentUnavailableView(
                    "No entries",
                    systemImage: "scalemass",
                    description: Text("Log a weight from the Body screen to start the history.")
                )
            } else {
                List {
                    ForEach(Array(weights.enumerated()), id: \.element.persistentModelID) { idx, entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            row(entry: entry, prev: idx + 1 < weights.count ? weights[idx + 1] : nil)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                entry.deletedFromIndex = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Weight history")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEntry) { entry in
            WeightEntryDetailSheet(entry: entry)
        }
    }

    private func row(entry: WeightEntry, prev: WeightEntry?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(absoluteDateString(entry.date))
                    .font(.subheadline)
                HStack(spacing: 6) {
                    Text(sourceCaption(entry.source))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    if entry.hasBodyFat {
                        Text("· BF \(String(format: "%.1f", entry.bodyFatPercent))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    if entry.hasLeanMass {
                        Text("· LM \(formatKg(entry.leanMassKg)) kg")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(formatKg(entry.weightKg)) kg")
                    .font(.body.monospacedDigit())
                if let prev {
                    let delta = entry.weightKg - prev.weightKg
                    HStack(spacing: 2) {
                        Image(systemName: delta < 0 ? "arrow.down" : delta > 0 ? "arrow.up" : "minus")
                            .font(.caption2)
                        Text(formatKg(abs(delta)))
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func sourceCaption(_ s: WeightSource) -> String {
        switch s {
        case .renpho:    "RENPHO"
        case .healthkit: "HEALTH"
        case .manual:    "MANUAL"
        }
    }

    private func absoluteDateString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy · HH:mm"
        return f.string(from: d)
    }

    private func formatKg(_ kg: Double) -> String {
        SafeFormat.decimal(kg)
    }
}
