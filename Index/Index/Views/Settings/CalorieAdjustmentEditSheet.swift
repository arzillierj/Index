import SwiftUI

/// Single-field edit sheet for `Profile.calorieAdjustmentKcal`.
/// Slider + live readout; range −1000 to +1000 kcal in 50-kcal steps.
/// Negative = deficit (cutting), positive = surplus (bulking),
/// zero = maintenance. Per the spec the user can edit this even when
/// `Goal == .maintain` (some users maintain at slight surplus / deficit).
struct CalorieAdjustmentEditSheet: View {
    let onError: (String) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProfileService.self) private var profileService

    @State private var draft: Double = 0

    private static let range: ClosedRange<Double> = -1000...1000
    private static let step: Double = 50

    var body: some View {
        NavigationStack {
            Form {
                Section("Calorie adjustment") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(formattedValue)
                                .font(.system(size: 32, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.primary)
                            Text("kcal/day")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Slider(value: $draft, in: Self.range, step: Self.step) {
                            Text("Calorie adjustment")
                        } minimumValueLabel: {
                            Text("−1000")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        } maximumValueLabel: {
                            Text("+1000")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .tint(IndexAccent.green)
                        Text(directionHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Calorie adjustment")
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
                draft = profileService.activeProfile?.calorieAdjustmentKcal ?? 0
            }
        }
        .tint(IndexAccent.green)
    }

    private var formattedValue: String {
        let i = Int(draft.rounded())
        if i > 0 { return "+\(i)" }
        return "\(i)"
    }

    private var directionHint: String {
        let i = Int(draft.rounded())
        switch i {
        case ..<0:  return "Deficit — applied as a subtraction from TDEE."
        case 0:     return "No adjustment."
        default:    return "Surplus — applied as an addition to TDEE."
        }
    }

    private func save() {
        do {
            try profileService.updateCalorieAdjustment(draft, in: context)
            dismiss()
        } catch {
            onError("Couldn't save calorie adjustment. Try again.")
            dismiss()
        }
    }
}
