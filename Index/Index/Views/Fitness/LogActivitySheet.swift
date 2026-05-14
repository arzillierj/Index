import SwiftUI

/// The activity picker the LOG button on Fitness presents.
/// Six rows fan out to per-activity log flows; a "My exercises" link under
/// the Strength row pushes to the strength library (no logging).
struct LogActivitySheet: View {
    let onSelect: (LogDestination) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    activityRow(title: "Strength session", icon: "dumbbell.fill", choice: .strength)
                    NavigationLink {
                        StrengthLibraryView()
                    } label: {
                        Label("My exercises", systemImage: "list.bullet")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    activityRow(title: "Cycling", icon: "bicycle", choice: .cycling)
                    activityRow(title: "Running", icon: "figure.run", choice: .running)
                    activityRow(title: "Swimming", icon: "figure.pool.swim", choice: .swimming)
                    activityRow(title: "Squash", icon: "figure.squash", choice: .squash)
                    activityRow(title: "Other", icon: "bolt.fill", choice: .other)
                }
            }
            .navigationTitle("What did you do?")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func activityRow(title: String, icon: String, choice: LogDestination) -> some View {
        Button {
            onSelect(choice)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Activities the picker can route to. The parent (FitnessMainView)
/// translates the choice into the appropriate sheet/fullScreenCover.
enum LogDestination: String, Hashable {
    case strength
    case cycling
    case running
    case swimming
    case squash
    case other
}
