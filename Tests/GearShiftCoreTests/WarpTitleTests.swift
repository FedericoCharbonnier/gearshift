@testable import GearShiftCore

func runWarpTitleTests() {
    suite("WarpTitle: normalized strips only a real status glyph") {
        expectEqual(WarpTitle.normalized("✳ Option help"), "Option help")
        expectEqual(WarpTitle.normalized("◑ Shiftcc app"), "Shiftcc app")
        expectEqual(WarpTitle.normalized("◐ ABC-123 add parent"), "ABC-123 add parent")
        expectEqual(WarpTitle.normalized("⠋ x"), "x")
        expectEqual(WarpTitle.normalized("· dots"), "dots")
        expectEqual(WarpTitle.normalized("✳  spaced  "), "spaced")
        // No glyph: the title is kept whole, ASCII punctuation included.
        expectEqual(WarpTitle.normalized("plain title"), "plain title")
        expectEqual(WarpTitle.normalized("-zsh"), "-zsh")
        expectEqual(WarpTitle.normalized("~/x"), "~/x")
        expectEqual(WarpTitle.normalized("(venv) GearShift"), "(venv) GearShift")
        expectEqual(WarpTitle.normalized("~"), "~")
        expectEqual(WarpTitle.normalized("3 tests"), "3 tests")
        expectEqual(WarpTitle.normalized("Élan"), "Élan")
        expectEqual(WarpTitle.normalized(""), "")
        // A glyph must be followed by a space and a title.
        expectEqual(WarpTitle.normalized("✳"), "✳")
        expectEqual(WarpTitle.normalized("✳GearShift"), "✳GearShift")
    }

    suite("WarpTitle: parse") {
        expectEqual(WarpTitle.parse("✳ GearShift")?.glyph, "✳")
        expectEqual(WarpTitle.parse("✳ GearShift")?.title, "GearShift")
        expectEqual(WarpTitle.parse("◑  GearShift")?.title, "GearShift")
        expectEqual(WarpTitle.parse("⠋ GearShift")?.glyph, "⠋")
        expect(WarpTitle.parse("GearShift") == nil, "no glyph")
        expect(WarpTitle.parse("- zsh") == nil, "ASCII punctuation is not a glyph")
        expect(WarpTitle.parse("~ x") == nil, "a tilde is not a glyph")
        expect(WarpTitle.parse("É x") == nil, "a non-ASCII letter is not a glyph")
        expect(WarpTitle.parse("٣ x") == nil, "a non-ASCII digit is not a glyph")
        expect(WarpTitle.parse("\u{00A0} x") == nil, "a non-ASCII space is not a glyph")
        expect(WarpTitle.parse("✳\u{FE0F} x") == nil, "a glyph is a single scalar (no variation selector)")
        expect(WarpTitle.parse("✳\u{00A0}x") == nil, "the separator is a plain space")
        expect(WarpTitle.parse("✳ ") == nil, "a bare glyph has no title")
    }

    suite("WarpTitle: matches requires a glyph") {
        let glyphTitles = ["✳ GearShift", "◑  GearShift", "⠋ GearShift", "◐ GearShift", "✢ GearShift", "✶ GearShift", "✻ GearShift", "✽ GearShift", "· GearShift", "◒ GearShift", "◓ GearShift"]
        for windowTitle in glyphTitles {
            expect(WarpTitle.matches(windowTitle: windowTitle, sessionTitle: "GearShift"), "\(windowTitle) matches")
        }
        for plain in ["GearShift", "-zsh", "~/x", "(venv) GearShift", "~", "· GearShift 2", "✳GearShift"] {
            expect(!WarpTitle.matches(windowTitle: plain, sessionTitle: "GearShift"), "\(plain) must not match")
        }
        expect(!WarpTitle.matches(windowTitle: "-zsh", sessionTitle: "zsh"), "zsh must not match -zsh")
        expect(!WarpTitle.matches(windowTitle: "- zsh", sessionTitle: "zsh"), "ASCII dash isn't a glyph")
        expect(WarpTitle.matches(windowTitle: "✳ Shiftcc app", sessionTitle: " Shiftcc app "), "session title whitespace ignored")
        expect(!WarpTitle.matches(windowTitle: "◑ shiftcc app", sessionTitle: "Shiftcc app"), "case-sensitive")
        expect(!WarpTitle.matches(windowTitle: "◑ Shiftcc app 2", sessionTitle: "Shiftcc app"), "whole title")
        expect(!WarpTitle.matches(windowTitle: "✳", sessionTitle: ""), "an empty title never matches")
        expect(!WarpTitle.matches(windowTitle: "✳ x", sessionTitle: ""), "an empty session title never matches")
    }

    suite("WarpTitle: idle glyph") {
        expect(WarpTitle.isIdle(windowTitle: "✳ GearShift"), "✳ is idle")
        expect(!WarpTitle.isIdle(windowTitle: "◐ GearShift"), "◐ is working")
        expect(!WarpTitle.isIdle(windowTitle: "◑ GearShift"), "◑ is working")
        expect(!WarpTitle.isIdle(windowTitle: "⠋ GearShift"), "braille spinner is working")
        expect(!WarpTitle.isIdle(windowTitle: "GearShift"), "no glyph is not idle")
    }
}
