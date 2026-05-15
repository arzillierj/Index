import SwiftUI

/// Read-only Apple Health status sheet. Surfaces:
///   - connection state (Connected / Not connected)
///   - a "Re-authorize" button when state is not authorized
///   - a "View in Health.app" deep link
///
/// Phase 7b will layer in the import-toggle UX; this sheet is the
/// status panel reachable from the "Status" row in SettingsView.
struct HealthStatusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var hkService

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Connection")
                        Spacer()
                        Text(connectionLabel)
                            .foregroundStyle(connectionColor)
                    }
                } footer: {
                    Text(connectionFooter)
                        .font(.caption2)
                }

                if !hkService.isAuthorized {
                    Section {
                        Button {
                            Task { await hkService.requestAuthorization() }
                        } label: {
                            Label("Connect Apple Health", systemImage: "heart.text.square")
                        }
                    } footer: {
                        Text("If you've previously denied, you'll need to re-enable Index in the Health app's Sources tab.")
                            .font(.caption2)
                    }
                }

                Section {
                    Link(destination: URL(string: "x-apple-health://")!) {
                        Label("Open Health app", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .navigationTitle("Apple Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .tint(IndexAccent.green)
    }

    private var connectionLabel: String {
        hkService.isAuthorized ? "Connected" : "Not connected"
    }

    private var connectionColor: Color {
        hkService.isAuthorized ? IndexAccent.green : .red
    }

    private var connectionFooter: String {
        if hkService.isAuthorized {
            "Index is reading your weight, body composition, workouts, heart rate, HRV, and VO2 max. It only writes manual weight entries back."
        } else {
            "Index can't read or write Apple Health data. Connect to enable workout auto-import + body composition history."
        }
    }
}
