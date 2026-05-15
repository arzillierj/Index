import SwiftUI

/// Every color used in Index. Single source of truth — to change any
/// color anywhere in the app, edit the hex string in this file. Do not
/// hardcode colors anywhere else in the codebase.
enum IndexPalette {

    // BRAND — accents used app-wide for primary actions and identity
    enum Brand {
        static let primary   = Color(hex: "#1E3A8A")  // French Blue
        static let secondary = Color(hex: "#FCB07E")  // Sandy Coral
    }

    // SURFACES — backgrounds, cards, dividers
    enum Surface {
        static let background = Color(hex: "#FAF8F5")  // Warm alabaster page
        static let card       = Color(hex: "#EBE9E9")  // Warm gray cards
        static let divider    = Color(hex: "#D6D3CE")  // Warm hairline
    }

    // TEXT — hierarchy
    enum Text {
        static let primary   = Color(hex: "#1A1A1A")   // Near-black, editorial
        static let secondary = Color(hex: "#6E6E73")   // Captions, labels
        static let tertiary  = Color(hex: "#AEAEB2")   // Placeholders, hints
        static let onAccent  = Color(hex: "#FFFFFF")   // Text on filled accents
    }

    // SEMANTIC — meaning-bearing status colors
    enum Semantic {
        static let success = Color(hex: "#34C759")  // On track, positive
        static let warning = Color(hex: "#FF9500")  // Approaching limit
        static let error   = Color(hex: "#FF3B30")  // Destructive, alerts
    }

    // DATA — visualization colors with stable semantic meaning
    // These DO NOT change per module — red always means HR, teal
    // always means efficiency, etc.
    enum Data {
        static let heartRate  = Color(hex: "#FF3B30")  // BPM, HR traces
        static let distance   = Color(hex: "#007AFF")  // km, m
        static let time       = Color(hex: "#FF9500")  // Duration, pace
        static let efficiency = Color(hex: "#5AC8FA")  // SWOLF, technique
        static let energy     = Color(hex: "#FF6B35")  // kcal
        static let protein    = Color(hex: "#A855F7")  // Protein g
        static let carbs      = Color(hex: "#FACC15")  // Carbs g
        static let fat        = Color(hex: "#84CC16")  // Fat g
    }

    // MODULES — per-module identifying accents
    enum Module {
        static let body      = Color(hex: "#1E3A8A")  // French Blue
        static let fitness   = Color(hex: "#FCB07E")  // Sandy Coral
        static let nutrition = Color(hex: "#4DBE7D")  // Teal
        static let settings  = Color(hex: "#1E3A8A")  // French Blue (same as Body)
    }

    // ACTIONS — interactive element colors
    enum Action {
        static let destructive = Color(hex: "#FF3B30")
        static let disabled    = Color(hex: "#C7C7CC")
    }
}

extension Color {
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
