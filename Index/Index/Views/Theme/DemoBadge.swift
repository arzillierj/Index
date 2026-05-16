import SwiftUI

/// Small "DEMO" pill rendered next to each module's page title
/// when `DemoMode.isEnabled`. Persistent so the user can never
/// mistake demo data for real data. Tasteful enough to live in
/// a showcase screenshot — uppercased monospaced caption,
/// sandy-coral fill, white text, soft rounded rect.
///
/// Hidden entirely when demo mode is off — the call site can
/// drop this view unconditionally and the body collapses to
/// `EmptyView` content.
struct DemoBadge: View {
    var body: some View {
        if DemoMode.isEnabled {
            Text("DEMO")
                .font(.caption2.weight(.semibold))
                .kerning(1.2)
                .monospaced()
                .foregroundStyle(IndexPalette.Text.onAccent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(IndexPalette.Module.fitness)
                .clipShape(.capsule)
        }
    }
}
