import SwiftUI
import SwiftData

/// Pushed from `NutritionMainView` via the "See all" link next
/// to TODAY'S LOG. Shows every NutritionEntry the user has
/// logged, grouped by meal type (Breakfast / Lunch / Dinner /
/// Snack), newest-first within each section. Tapping a row
/// invokes `onRequestRelog` — the parent dismisses this screen
/// and opens `LogMealManualSheet` pre-filled with the original's
/// name, kcal, macros, and meal type. Saving creates a NEW
/// entry dated today; the original is untouched.
///
/// Duplicates are intentional: the same food appears once per
/// time it was logged. The deduplicated view is the FREQUENT
/// chip row on the main screen; this is the full log.
struct FoodHistoryView: View {
    /// Called when the user taps a past entry. Parent
    /// (NutritionMainView) pops this screen (`dismiss()` below)
    /// and routes through its existing `manualEntryPrefill`
    /// state so the re-log goes through the same sheet path AI
    /// / barcode / frequent-foods already use.
    let onRequestRelog: (NutritionEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    @Query(sort: \NutritionEntry.date, order: .reverse)
    private var entries: [NutritionEntry]

    /// Display order for the meal-type sections — Breakfast →
    /// Lunch → Dinner → Snack, matching the meal-type enum's
    /// declaration order. Sections with zero entries collapse
    /// out entirely (no empty headers).
    private static let mealTypeOrder: [MealType] = [.breakfast, .lunch, .dinner, .snack]

    private var entriesByMealType: [MealType: [NutritionEntry]] {
        Dictionary(grouping: entries, by: \.mealType)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(IndexPalette.Surface.background.ignoresSafeArea())
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(IndexPalette.Surface.background, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "fork.knife")
                .font(.system(size: 36))
                .foregroundStyle(IndexPalette.Text.tertiary)
            Text("No meals logged yet")
                .font(IndexFont.rowTitle)
                .foregroundStyle(IndexPalette.Text.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - List

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Self.mealTypeOrder, id: \.self) { type in
                    if let rows = entriesByMealType[type], !rows.isEmpty {
                        section(type: type, rows: rows)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private func section(type: MealType, rows: [NutritionEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(type.label.uppercased())
                .font(IndexFont.sectionCap)
                .kerning(0.8)
                .foregroundStyle(IndexPalette.Text.tertiary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, entry in
                    Button {
                        onRequestRelog(entry)
                        dismiss()
                    } label: {
                        row(entry: entry)
                    }
                    .buttonStyle(.plain)
                    if idx < rows.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(IndexPalette.Surface.card)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    /// Matches TODAY'S LOG row styling — same typography
    /// tokens (`IndexFont.rowTitle` / `rowSecondary` /
    /// `rowValue`), same kcal-with-unit alignment, same
    /// padding. The only difference is the trailing date
    /// (e.g. "12 May") in place of TODAY'S LOG's time.
    private func row(entry: NutritionEntry) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label.isEmpty ? "—" : entry.label)
                    .font(IndexFont.rowTitle)
                    .lineLimit(1)
                Text(dateString(entry.date))
                    .font(IndexFont.rowSecondary)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(SafeFormat.int(entry.kcal))
                    .font(IndexFont.rowValue)
                Text("kcal")
                    .font(IndexFont.tileUnit)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Hoisted formatter so it isn't rebuilt per row.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private func dateString(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return Self.dateFormatter.string(from: d)
    }
}
