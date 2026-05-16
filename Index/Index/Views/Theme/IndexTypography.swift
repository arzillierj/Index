import SwiftUI

/// Central type system. SF Pro across the board with
/// `.monospacedDigit()` on every helper that renders a number —
/// gives column-aligned digits without swapping font families.
/// Geist Mono was tried in a prior pass; its full-width `.` glyph
/// rendered decimals as "87 . 3" with floaty gaps, so the
/// experiment was rolled back to system font + tabular figures.
///
/// All tokens are point-size constants. Every numerical site in
/// every module must resolve to one of these — raw
/// `.font(.system(size:))` calls are forbidden outside this file
/// so the three modules stay typographically aligned (Body hero,
/// Fitness hero, Nutrition hero all render at the SAME size, etc.).
///
/// Dynamic Type support (partial — added with the layout
/// hardening pass):
///
///   - Small / mid tokens use semantic Font.TextStyle (`.body`,
///     `.subheadline`, `.caption`, etc.) so the system text-size
///     setting scales them. These are the body of the app's text:
///     row titles, captions, tile labels, tile units, section
///     caps, hero captions.
///   - Hero numerals (`hero` 56pt, `tileValue` 24pt, `heroUnit`
///     22pt) stay FIXED point sizes. SwiftUI's path to a scaling
///     system font at a specific point size is `Font.custom` with
///     a font name, which we don't use; the alternative
///     (ScaledMetric per call site) would require turning every
///     hero into a wrapper view. Hero Dynamic Type is therefore
///     DEFERRED — at large text sizes the surrounding caption
///     text grows around fixed-size hero numerals. Live-with-it
///     compromise; ship-blocker is layout breakage, not exact
///     hero scaling.
///   - The tile-clipping fix (Section 4 of the layout-hardening
///     spec) compensates: tile values carry `minimumScaleFactor`
///     so they shrink when growing units shove them. Even at
///     larger text sizes, tile content fits.
///
/// Section captions take `.kerning(0.8)` at the call site
/// (SwiftUI's `Font` doesn't carry tracking). Use the
/// `IndexFont.sectionCap` constant + the kerning modifier together.
enum IndexFont {

    /// 56pt bold, FIXED. Module hero numerals.
    /// - Body: "87.3"
    /// - Fitness: "2h 53m"
    /// - Nutrition: "2215", "173"
    /// - WorkoutDetailView / StrengthSessionDetailView: duration hero
    ///
    /// Does NOT scale with Dynamic Type — see file header. Pair
    /// with `.minimumScaleFactor` at call sites where the
    /// surrounding container constrains width.
    static let hero = Font.system(size: 56, weight: .bold)
        .monospacedDigit()

    /// 22pt regular, FIXED. Unit suffix next to a hero numeral.
    /// Sits at `.firstTextBaseline` of the hero so a "kg" /
    /// "kcal" / "g" reads as a quiet trailing label.
    static let heroUnit = Font.system(size: 22, weight: .regular)

    /// Caption line directly under a hero — relative dates ("3
    /// days ago"), target sub-lines ("/ 2137 kcal", "/ 167 g"),
    /// Fitness this-week sub-line ("4 sessions · 1865 kcal
    /// burned"). Scales with Dynamic Type via `.subheadline`
    /// semantic style.
    static let heroCaption = Font.system(.subheadline, weight: .regular)
        .monospacedDigit()

    /// Tile label above the value (BMI, BMR, TDEE, Carbs, Fat,
    /// HRV, VO2 max, Resting HR). Sentence-case. Scales with
    /// Dynamic Type via `.caption` semantic.
    static let tileLabel = Font.system(.caption, weight: .medium)

    /// 24pt semibold, FIXED. Numerical tile value (24.7, 1943,
    /// 2671, 23.3, 66.9, 74–90, 24, 46.3, 85, 262, 46). Doesn't
    /// scale with Dynamic Type — see file header. Pair with
    /// `.minimumScaleFactor(0.6)` at call sites so the tile
    /// shrinks the numeral instead of clipping its unit when
    /// the user runs a large text size.
    static let tileValue = Font.system(size: 24, weight: .semibold)
        .monospacedDigit()

    /// Unit suffix next to a tile value — "kcal", "%", "kg",
    /// "ms", "bpm", "g". Sits at `.firstTextBaseline` of the
    /// tile value with secondary foreground. Scales via `.caption`.
    static let tileUnit = Font.system(.caption, weight: .regular)

    /// Section captions: TODAY / COMPOSITION / VITALS / RECENT /
    /// FREQUENT / TODAY'S LOG / THIS WEEK / STEPS / PROFILE /
    /// GOAL / MODULES / ... Pass the string literal already
    /// uppercase so SwiftUI doesn't apply `.textCase`. Add
    /// `.kerning(0.8)` at the call site. Scales via `.caption2`.
    static let sectionCap = Font.system(.caption2, weight: .semibold)

    /// List-row title (Swimming / Squash / Risotto / Whey
    /// Isolate / Name / Age / Direction / etc.). Scales via
    /// `.body`.
    static let rowTitle = Font.system(.body, weight: .regular)

    /// List-row value rendered on the trailing side ("27m",
    /// "56m", "45m", "410 kcal", "108 kcal", "188 cm", "82 kg",
    /// word-only values like "Yannis" / "Cutting" / "Male" —
    /// monospacedDigit is a no-op on non-digit strings). Scales
    /// via `.body`.
    static let rowValue = Font.system(.body, weight: .regular)
        .monospacedDigit()

    /// Row sub-line ("Today" / "Yesterday" / "Tuesday" / "17:27"
    /// / "13:04"). Tabular digits keep time labels and dates
    /// column-aligned in feed lists. Scales via `.footnote`.
    static let rowSecondary = Font.system(.footnote, weight: .regular)
        .monospacedDigit()
}
