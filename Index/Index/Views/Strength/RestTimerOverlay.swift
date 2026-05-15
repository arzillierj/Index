import SwiftUI
import UIKit
import Combine

/// Translucent overlay that counts down from `durationSeconds` to 0. Auto-
/// dismisses with a success haptic at zero; tap-to-dismiss-early fires no
/// haptic. Used between sets in ActiveStrengthSessionView.
struct RestTimerOverlay: View {
    @Binding var isShowing: Bool
    let durationSeconds: Int

    @State private var startedAt: Date = .now
    @State private var remaining: Int

    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(isShowing: Binding<Bool>, durationSeconds: Int) {
        self._isShowing = isShowing
        self.durationSeconds = durationSeconds
        self._remaining = State(initialValue: durationSeconds)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("REST")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                    .tracking(2)
                Text(format(remaining))
                    .font(IndexFont.hero)
                    .foregroundStyle(.white)
                Text("Tap to dismiss")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) { isShowing = false }
        }
        .onReceive(timer) { _ in
            let elapsed = Int(Date.now.timeIntervalSince(startedAt))
            let next = max(0, durationSeconds - elapsed)
            if next != remaining {
                remaining = next
            }
            if next == 0 {
                let g = UINotificationFeedbackGenerator()
                g.notificationOccurred(.success)
                withAnimation(.easeOut(duration: 0.18)) { isShowing = false }
            }
        }
    }

    private func format(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return String(format: "%d:%02d", m, s)
    }
}
