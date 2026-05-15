import SwiftUI

/// Accent color for Index. Used for active toggle states, selected segments,
/// primary action buttons, and chevron tint on tappable rows. **Scoped to
/// Settings only** — the rest of the app stays on iOS-default tint until
/// a broader design pass decides where else to apply it.
///
/// To swap: change the hex string below. That's the only edit needed.
enum IndexAccent {
    static let primary = Color(hex: "#1E3A8A")
}

extension Color {
    /// Initialize a Color from a hex string like "#1E3A8A" or "1E3A8A".
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}
