import Foundation

/// Warp window titles are the active tab's title. Claude Code sets it to `<glyph> <session title>`
/// (e.g. `◑ Shiftcc app`); anything else in a tab (a shell, `~`, `(venv) x`) has no such glyph, and
/// must never be taken for a session.
///
/// Claude Code 2.1.282 draws `✳` when the session isn't busy (idle, or showing the user a dialog)
/// and alternates `◐`/`◑` while it works. Other glyphs are accepted for matching so that an older
/// or newer spinner still finds the tab, but only `✳` counts as idle.
public enum WarpTitle {
    public static let idleGlyph: Unicode.Scalar = "✳"

    /// `<glyph><one or more spaces><title>`, where the glyph is one non-ASCII scalar that isn't a
    /// letter, digit, space or control character. Nil for any other shape.
    public static func parse(_ windowTitle: String) -> (glyph: Unicode.Scalar, title: String)? {
        let scalars = windowTitle.unicodeScalars
        guard let glyph = scalars.first, isGlyph(glyph) else { return nil }
        let rest = scalars.dropFirst()
        guard rest.first == " " else { return nil }
        let title = String(String.UnicodeScalarView(rest)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return (glyph, title)
    }

    static func isGlyph(_ scalar: Unicode.Scalar) -> Bool {
        guard !scalar.isASCII else { return false }
        let properties = scalar.properties
        if properties.isAlphabetic || properties.isWhitespace || properties.numericType != nil {
            return false
        }
        switch properties.generalCategory {
        case .control, .format, .nonspacingMark, .spacingMark, .enclosingMark, .privateUse, .surrogate, .unassigned:
            return false
        default:
            return true
        }
    }

    /// The title without its glyph when it has one, else the whole (trimmed) title. Used to compare
    /// tabs while cycling, since the glyph animates on its own.
    public static func normalized(_ windowTitle: String) -> String {
        parse(windowTitle)?.title ?? windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Case-sensitive, like the titles themselves; a window title without a glyph never matches.
    public static func matches(windowTitle: String, sessionTitle: String) -> Bool {
        let target = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, let parsed = parse(windowTitle) else { return false }
        return parsed.title == target
    }

    public static func isIdle(windowTitle: String) -> Bool {
        parse(windowTitle)?.glyph == idleGlyph
    }
}
