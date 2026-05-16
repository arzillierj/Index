import SwiftUI

/// Edit sheet for `ClaudeService.monthlyBudgetUSD`. Range
/// $0.00 – $50.00 in $0.50 steps. Backed by UserDefaults under
/// `ClaudeService.monthlyBudgetKey`; default $2.00 on first use.
///
/// $0 is allowed (and effectively disables the AI feature — the
/// budget gate compares strictly `<` so spend always blocks).
/// $50 ceiling is a soft sanity bound; raise the upper here if a
/// legitimate use case ever appears.
struct AIBudgetEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ClaudeService.self) private var claudeService

    @State private var draft: Double = 2.0

    private static let range: ClosedRange<Double> = 0...50
    private static let step: Double = 0.5

    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly budget") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(formattedValue)
                                .font(IndexFont.hero)
                                .foregroundStyle(IndexPalette.Module.settings)
                            Spacer()
                        }
                        Slider(value: $draft, in: Self.range, step: Self.step) {
                            Text("Monthly budget")
                        } minimumValueLabel: {
                            Text("$0")
                                .font(IndexFont.rowSecondary)
                                .foregroundStyle(IndexPalette.Text.tertiary)
                        } maximumValueLabel: {
                            Text("$50")
                                .font(IndexFont.rowSecondary)
                                .foregroundStyle(IndexPalette.Text.tertiary)
                        }
                        .tint(IndexPalette.Module.settings)
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(IndexPalette.Text.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Monthly budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear {
                draft = claudeService.monthlyBudgetUSD
            }
        }
        .tint(IndexPalette.Module.settings)
    }

    private var formattedValue: String {
        String(format: "$%.2f", draft)
    }

    /// Short hint that explains the cap's behavior — useful first-
    /// time, low-signal afterwards but cheap to keep.
    private var hint: String {
        if draft <= 0 {
            return "Disabled — AI estimates will not be requested."
        }
        return "Estimates stop when this month's spend reaches the cap."
    }

    private func save() {
        claudeService.monthlyBudgetUSD = draft
        dismiss()
    }
}
