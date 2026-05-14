import SwiftUI

struct ContentView: View {
    @State private var draftReceived: OnboardingDraft? = nil

    var body: some View {
        if let draft = draftReceived {
            // P3.10 placeholder — P3.11 replaces this with the real
            // post-onboarding route into the Body tab.
            VStack(spacing: 8) {
                Text("Onboarding complete.")
                    .font(.title.italic())
                Text(draft.name.isEmpty ? "(no name)" : draft.name)
                    .foregroundStyle(.secondary)
                Text("userId: \(draft.userId)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding()
        } else {
            OnboardingView(identity: AppDependencies.identity) { draft in
                draftReceived = draft
            }
        }
    }
}

#Preview {
    ContentView()
}
