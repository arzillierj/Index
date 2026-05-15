import SwiftUI
import CoreText

/// Central font helpers. Geist Mono for numerical displays
/// (hero numerals, tile values, inline data), SF Pro (the system
/// default) for everything that is not a number — section captions,
/// labels, buttons, prose. The rule of thumb across the app is
/// "data is mono, words are sans" — a mixed line splits into two
/// `Text`s with their own font.
///
/// To swap the monospace family, change the PostScript-name strings
/// below in one place; all numerical sites pick it up.
enum IndexFont {

    // PostScript names — verified via the font's `name` table at
    // download time. If the bundled .ttf is replaced with a different
    // foundry's mono, update these to match the new file's PostScript
    // name (NOT the file name).
    private static let regular  = "GeistMono-Regular"
    private static let medium   = "GeistMono-Medium"
    private static let semibold = "GeistMono-SemiBold"
    private static let bold     = "GeistMono-Bold"

    /// Numerical hero display — bold, used for the biggest numbers
    /// on each module screen ("87.3", "1805", "2h 53m", "3'474").
    /// At the same point size, Geist Mono reads a hair heavier than
    /// SF Pro so callers may want to trim 2–4pt from the previous
    /// `.system(size:)` value when porting.
    static func monoHero(_ size: CGFloat) -> Font {
        .custom(bold, size: size)
    }

    /// Numerical tile / secondary number — semibold, used for tile
    /// values that aren't the hero (BMI, BMR, TDEE, macro tiles,
    /// per-row data points).
    static func monoTile(_ size: CGFloat) -> Font {
        .custom(semibold, size: size)
    }

    /// Numerical caption — regular weight, used for inline small
    /// numbers like "of 10'000 steps" target subtitles or row-side
    /// time labels (17:27).
    static func monoCaption(_ size: CGFloat) -> Font {
        .custom(regular, size: size)
    }

    /// Numerical medium-weight — half-step heavier than caption,
    /// half-step lighter than tile. Used for sub-line data values
    /// that need more presence than a caption but less than a tile.
    static func monoMedium(_ size: CGFloat) -> Font {
        .custom(medium, size: size)
    }

    /// Builds a single `Text` that switches between `numberFont` and
    /// `textFont` per character run — digits + decimal / sign /
    /// thousands-separator characters render in mono, everything else
    /// stays sans. Used for free-form Settings values where the
    /// row helper doesn't know up-front whether the string is a
    /// number-with-unit ("188 cm", "+500 kcal/day") or pure prose
    /// ("Yannis", "Cutting").
    ///
    /// Strings with no digits round-trip as one sans `Text`, so it's
    /// safe to apply unconditionally to every row value.
    static func mixedNumeric(
        _ s: String,
        numberFont: Font,
        textFont: Font
    ) -> Text {
        let numericChars: Set<Character> = Set("0123456789.,-+'")
        var out = Text("")
        var buf = ""
        var bufIsNumeric: Bool? = nil
        let flush: (inout Text, String, Bool) -> Void = { result, segment, isNum in
            guard !segment.isEmpty else { return }
            result = result + Text(segment).font(isNum ? numberFont : textFont)
        }
        for ch in s {
            let isNum = numericChars.contains(ch)
            if let current = bufIsNumeric {
                if current == isNum {
                    buf.append(ch)
                } else {
                    flush(&out, buf, current)
                    buf = String(ch)
                    bufIsNumeric = isNum
                }
            } else {
                buf.append(ch)
                bufIsNumeric = isNum
            }
        }
        if let current = bufIsNumeric {
            flush(&out, buf, current)
        }
        return out
    }
}

/// Runtime registration of the bundled Geist Mono .ttf files. The
/// project's Info.plist is generated via INFOPLIST_KEY_* settings,
/// which doesn't support array-typed plist keys like UIAppFonts.
/// CTFontManagerRegisterFontURLs registers the fonts with the
/// current process at launch, after which `Font.custom(_:size:)`
/// resolves them normally.
///
/// Invoked from `IndexApp.init`. Safe to call multiple times —
/// re-registration of an already-registered URL is a no-op (the
/// matching CT error is filtered).
enum IndexFontRegistration {
    static func registerBundledFonts() {
        let postscriptNames = [
            "GeistMono-Regular",
            "GeistMono-Medium",
            "GeistMono-SemiBold",
            "GeistMono-Bold",
        ]
        let urls: [URL] = postscriptNames.compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "ttf")
        }
        guard !urls.isEmpty else {
            print("[IndexFontRegistration] no Geist Mono TTFs found in bundle — falling back to system font for numerical displays")
            return
        }
        // The bulk `CTFontManagerRegisterFontURLs` API in modern iOS
        // takes an async registration-handler closure instead of an
        // out-error array. For a one-shot launch register we iterate
        // the single-URL `CTFontManagerRegisterFontsForURL` synchronous
        // variant — clearer error handling, and we can skip the
        // "already registered" code so repeat launches stay quiet.
        for url in urls {
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &error
            )
            if !ok, let err = error?.takeRetainedValue() {
                let nsErr = err as Error as NSError
                // 105 = kCTFontManagerErrorAlreadyRegistered. Benign;
                // happens on warm reloads where the font is still
                // resident with the process from the prior launch.
                if nsErr.code != 105 {
                    print("[IndexFontRegistration] register error for \(url.lastPathComponent): \(err)")
                }
            }
        }
    }
}
