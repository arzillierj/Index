import SwiftUI

/// Central type system. SF Pro across the board with
/// `.monospacedDigit()` on every helper that renders a number —
/// gives column-aligned digits without swapping font families.
/// Geist Mono was tried in the previous pass; its full-width `.`
/// glyph rendered decimals as "87 . 3" with floaty gaps, so the
/// experiment was rolled back to system font + tabular figures.
///
/// All tokens are point-size constants. Every numerical site in
/// every module must resolve to one of these — raw
/// `.font(.system(size:))` calls are forbidden outside this file
/// so the three modules stay typographically aligned (Body hero,
/// Fitness hero, Nutrition hero all render at the SAME size, etc.).
///
/// Section captions take `.kerning(0.8)` at the call site
/// (SwiftUI's `Font` doesn't carry tracking). Use the
/// `IndexFont.sectionCap` constant + the kerning modifier together.
enum IndexFont {

    /// 56pt bold. Module hero numerals.
    /// - Body: "87.3"
    /// - Fitness: "2h 53m"
    /// - Fitness Today / Steps: "3'474"
    /// - Nutrition: "2215", "173"
    /// - WorkoutDetailView / StrengthSessionDetailView: duration hero
    static let hero = Font.system(size: 56, weight: .bold)
        .monospacedDigit()

    /// 22pt regular. Unit suffix next to a hero numeral. Sits at
    /// `.firstTextBaseline` of the hero so a "kg" / "kcal" / "g"
    /// reads as a quiet trailing label.
    static let heroUnit = Font.system(size: 22, weight: .regular)

    /// 15pt regular. Caption line directly under a hero — relative
    /// dates ("3 days ago"), target sub-lines ("/ 2137 kcal", "/ 167
    /// g"), Fitness this-week sub-line ("4 sessions · 1865 kcal
    /// burned"). Numbers inside are tabular via monospacedDigit.
    static let heroCaption = Font.system(size: 15, weight: .regular)
        .monospacedDigit()

    /// 13pt medium. Tile label above the value (BMI, BMR, TDEE,
    /// Carbs, Fat, HRV, VO2 max, Resting HR). Sentence-case.
    static let tileLabel = Font.system(size: 13, weight: .medium)

    /// 24pt semibold. Numerical tile value (24.7, 1943, 2671, 23.3,
    /// 66.9, 74–90, 24, 46.3, 85, 262, 46).
    static let tileValue = Font.system(size: 24, weight: .semibold)
        .monospacedDigit()

    /// 13pt regular. Unit suffix next to a tile value — "kcal", "%",
    /// "kg", "ms", "bpm", "g". Sits at `.firstTextBaseline` of the
    /// tile value with secondary foreground.
    static let tileUnit = Font.system(size: 13, weight: .regular)

    /// 12pt semibold. Section captions: TODAY / COMPOSITION /
    /// VITALS / RECENT / FREQUENT / TODAY'S LOG / THIS WEEK / STEPS
    /// / PROFILE / GOAL / MODULES / ... Pass the string literal
    /// already uppercase so SwiftUI doesn't have to apply textCase.
    /// Add `.kerning(0.8)` at the call site.
    static let sectionCap = Font.system(size: 12, weight: .semibold)

    /// 17pt regular. List-row title (Swimming / Squash / Risotto /
    /// Whey Isolate / Name / Age / Direction / etc.).
    static let rowTitle = Font.system(size: 17, weight: .regular)

    /// 17pt regular with tabular figures. List-row value rendered
    /// on the trailing side ("27m", "56m", "45m", "410 kcal", "108
    /// kcal", "188 cm", "82 kg", and word-only values like "Yannis"
    /// / "Cutting" / "Male" — monospacedDigit is a no-op on
    /// non-digit strings).
    static let rowValue = Font.system(size: 17, weight: .regular)
        .monospacedDigit()

    /// 13pt regular. Row sub-line ("Today" / "Yesterday" /
    /// "Tuesday" / "17:27" / "13:04"). Tabular digits keep time
    /// labels and dates column-aligned in feed lists.
    static let rowSecondary = Font.system(size: 13, weight: .regular)
        .monospacedDigit()
}
