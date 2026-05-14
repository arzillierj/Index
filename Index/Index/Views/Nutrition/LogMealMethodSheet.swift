import SwiftUI

/// Two-row method picker: scan a barcode or enter manually. The parent
/// owns the actual presentation — this sheet just reports which path the
/// user chose and dismisses.
struct LogMealMethodSheet: View {
    enum Method { case scan, manual }

    let onSelect: (Method) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                methodRow(
                    icon: "barcode.viewfinder",
                    title: "Scan barcode",
                    subtitle: "Look up packaged-food nutrition data.",
                    action: { onSelect(.scan) }
                )
                methodRow(
                    icon: "square.and.pencil",
                    title: "Enter manually",
                    subtitle: "Type in label, calories, and macros.",
                    action: { onSelect(.manual) }
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func methodRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
