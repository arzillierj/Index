import Foundation

/// Defensive number formatters. Every `Int(Double)` conversion in display
/// code goes through one of these so a corrupted SwiftData value can't
/// trap the app on launch. The observed-in-the-wild incident on
/// 2026-05-14 was a WeightEntry with weightKg ~5×10³⁸ kg — far above
/// Int's range, so the previous BodyView.formatKg crashed at
/// `Int(kg)` before any view could render to let the user delete the
/// row.
///
/// All helpers return "—" for non-finite (`nan`/`inf`) values or
/// values whose magnitude exceeds a sane threshold.
enum SafeFormat {

    /// Format a Double with up to 1 decimal place. Whole numbers render
    /// without decimals. Used for kg, km, and any other decimal display.
    static func decimal(_ value: Double, threshold: Double = 1e9) -> String {
        guard value.isFinite, abs(value) < threshold else { return "—" }
        if value == floor(value) {
            return "\(Int(value))"
        } else {
            return String(format: "%.1f", value)
        }
    }

    /// Format a Double as a rounded integer. Used for kcal, BMR, TDEE,
    /// HRV (ms), and ideal-range endpoints.
    static func int(_ value: Double, threshold: Double = 1e9) -> String {
        guard value.isFinite, abs(value) < threshold else { return "—" }
        return "\(Int(value.rounded()))"
    }

    /// Format a percentage with 1 decimal place. Used for body fat % and
    /// any other percentage display.
    static func percent(_ value: Double, threshold: Double = 1e6) -> String {
        guard value.isFinite, abs(value) < threshold else { return "—" }
        return String(format: "%.1f", value)
    }
}
