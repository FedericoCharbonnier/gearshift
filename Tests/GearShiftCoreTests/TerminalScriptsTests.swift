@testable import GearShiftCore

func runTerminalScriptsTests() {
    suite("TerminalScripts: focus sources") {
        let tty = "/dev/ttys007"
        guard let terminal = TerminalScripts.focusSource(kind: .terminal, tty: tty),
              let iterm = TerminalScripts.focusSource(kind: .iterm, tty: tty)
        else { return expect(false, "sources for Terminal and iTerm2") }
        // Never launches the app: the running check comes before anything is sent to it.
        expect(terminal.hasPrefix(#"if application id "com.apple.Terminal" is not running then return "not running""#), "Terminal guard first")
        expect(iterm.hasPrefix(#"if application id "com.googlecode.iterm2" is not running then return "not running""#), "iTerm guard first")
        expect(terminal.contains(#"if (tty of aTab) is "/dev/ttys007" then"#), "Terminal matches tabs by tty")
        expect(iterm.contains(#"if (tty of session s of aTab) is "/dev/ttys007" then"#), "iTerm matches sessions by tty")
        // iTerm2 fails with -1728 on `contents of` a repeat-loop item (seen live), so matches are
        // kept as window id + indexes.
        expect(!iterm.contains("contents of"), "iTerm never dereferences loop items")
        expect(iterm.contains("set matchWindow to window id matchWindowId"), "iTerm finds the window again by id")
        for source in [terminal, iterm] {
            expect(source.contains(#"if matchCount is not 1 then return "matches " & matchCount"#), "exactly one match")
            expect(source.contains("with timeout of"), "bounded")
            // Keys are typed separately, after checks: never through the terminal's own commands.
            expect(!source.contains("write text") && !source.contains("do script") && !source.contains("keystroke"), "no typing")
        }
        expect(terminal.contains("set selected of matchTab to true") && terminal.contains("set index of matchWindow to 1"), "Terminal selects")
        expect(iterm.contains("select matchTab") && iterm.contains("select session matchSessionIndex of matchTab") && iterm.contains("select matchWindow"), "iTerm selects")
        // Nothing to find for Warp or other terminals, or with a tty that isn't one.
        expectEqual(TerminalScripts.focusSource(kind: .warp, tty: tty), nil)
        expectEqual(TerminalScripts.focusSource(kind: .other, tty: tty), nil)
        expectEqual(TerminalScripts.focusSource(kind: .terminal, tty: #"/dev/ttys1" then quit"#), nil)
        expectEqual(TerminalScripts.focusSource(kind: .iterm, tty: ""), nil)
    }

    suite("TerminalScripts: iTerm2 background writes") {
        let tty = "/dev/ttys007"
        guard let text = TerminalScripts.writeSource(kind: .iterm, tty: tty, input: .text("/model opus[1m]")),
              let enter = TerminalScripts.writeSource(kind: .iterm, tty: tty, input: .carriageReturn)
        else { return expect(false, "write sources for iTerm2") }
        for source in [text, enter] {
            // Never launches iTerm2, and gives up rather than hang.
            expect(source.hasPrefix(#"if application id "com.googlecode.iterm2" is not running then return "not running""#), "guard first")
            expect(source.contains("with timeout of"), "bounded")
            // Exactly one session on the tty, counted by this same script, then read again right
            // before the write, which goes to that session only.
            expect(source.contains(#"if (tty of session s of aTab) is "/dev/ttys007" then"#), "matches sessions by tty")
            expect(source.contains(#"if matchCount is not 1 then return "matches " & matchCount"#), "exactly one match")
            expect(!source.contains("contents of"), "never dereferences loop items (-1728)")
            let recheck = source.range(of: #"if (tty of matchSession) is not "/dev/ttys007" then return "matches 0""#)
            let write = source.range(of: "tell matchSession to write text ")
            expect(recheck != nil && write != nil && recheck!.upperBound <= write!.lowerBound, "tty read again right before the write")
            expect(source.components(separatedBy: "write text").count == 2, "one write")
            expect(source.contains(" newline false"), "iTerm2 adds no line ending of its own")
            // In the background: nothing is brought forward, selected or read for focus.
            for change in ["activate", "select", "set index", "frontmost", "miniaturized", "reveal", "keystroke", "do script"] {
                expect(!source.localizedCaseInsensitiveContains(change), "no \(change)")
            }
        }
        expect(text.contains(#"tell matchSession to write text "/model opus[1m]" newline false"#), "the command's text alone")
        // Return is a lone CR: Claude Code's raw-mode input takes CR as Enter (LF would be Ctrl-J).
        expect(enter.contains("tell matchSession to write text (character id 13) newline false"), "a lone carriage return")

        // Only iTerm2 is written to in the background, only on a valid tty.
        expectEqual(TerminalScripts.writeSource(kind: .terminal, tty: tty, input: .text("/model opus")), nil)
        expectEqual(TerminalScripts.writeSource(kind: .warp, tty: tty, input: .carriageReturn), nil)
        expectEqual(TerminalScripts.writeSource(kind: .other, tty: tty, input: .carriageReturn), nil)
        expectEqual(TerminalScripts.writeSource(kind: .iterm, tty: #"/dev/ttys1" then quit"#, input: .carriageReturn), nil)
        expectEqual(TerminalScripts.writeSource(kind: .iterm, tty: "", input: .text("/model opus")), nil)
        // No text that could submit (or edit) the line by itself, and nothing empty.
        for bad in ["", "/model opus\r", "/model opus\n", "/effort\u{1B}[A", "/model\topus", "/model opus\u{7F}", "\u{85}"] {
            expectEqual(TerminalScripts.writeSource(kind: .iterm, tty: tty, input: .text(bad)), nil)
        }
    }

    suite("TerminalScripts: AppleScript string literals") {
        expectEqual(TerminalScripts.appleScriptLiteral("/effort max"), #""/effort max""#)
        expectEqual(TerminalScripts.appleScriptLiteral(#"say "hi""#), #""say \"hi\"""#)
        expectEqual(TerminalScripts.appleScriptLiteral(#"a\b"#), #""a\\b""#)
        // The backslash is escaped first, so an escaped quote can't be undone.
        expectEqual(TerminalScripts.appleScriptLiteral(#"\""#), #""\\\"""#)
        expectEqual(TerminalScripts.appleScriptLiteral(""), #""""#)
        let source = TerminalScripts.writeSource(kind: .iterm, tty: "/dev/ttys007", input: .text(#"x" & (do shell script "id") & "\"#))
        expect(source?.contains(#"write text "x\" & (do shell script \"id\") & \"\\" newline false"#) ?? false, "quotes can't end the literal")
        // Every model ShiftCommands accepts is written verbatim.
        for model in ["opus", "opus[1m]", "claude-opus-5-5", "us.anthropic.claude:0"] {
            expectEqual(TerminalScripts.appleScriptLiteral("/model \(model)"), "\"/model \(model)\"")
        }
    }

    suite("TerminalScripts: front sources only read") {
        guard let terminal = TerminalScripts.frontSource(kind: .terminal), let iterm = TerminalScripts.frontSource(kind: .iterm) else {
            return expect(false, "sources")
        }
        expect(terminal.contains("tty of selected tab of frontWindow") && terminal.contains("set frontWindow to front window"), "Terminal's front tab")
        expect(iterm.contains("tty of current session of frontWindow") && iterm.contains("set frontWindow to current window"), "iTerm's current pane")
        for source in [terminal, iterm] {
            expect(source.contains(#"if not frontmost then return "not frontmost""#), "frontmost first")
            let changes = ["\tselect ", "set selected", "activate", "set index", "miniaturized"]
            expect(!changes.contains(where: source.contains), "changes nothing")
        }
        expectEqual(TerminalScripts.frontSource(kind: .warp), nil)
        expectEqual(TerminalScripts.frontSource(kind: .other), nil)
    }

    suite("TerminalScripts: answers") {
        expectEqual(TerminalScripts.focusOutcome("focused"), .focused)
        expectEqual(TerminalScripts.focusOutcome("not running"), .notRunning)
        expectEqual(TerminalScripts.focusOutcome("matches 0"), .matches(0))
        expectEqual(TerminalScripts.focusOutcome("matches 2"), .matches(2))
        expectEqual(TerminalScripts.focusOutcome("matches 1"), .unexpected("matches 1"))
        expectEqual(TerminalScripts.focusOutcome(""), .unexpected(""))

        expectEqual(TerminalScripts.writeOutcome("sent"), .sent)
        expectEqual(TerminalScripts.writeOutcome("not running"), .notRunning)
        expectEqual(TerminalScripts.writeOutcome("matches 0"), .matches(0))
        expectEqual(TerminalScripts.writeOutcome("matches 3"), .matches(3))
        expectEqual(TerminalScripts.writeOutcome("matches 1"), .unexpected("matches 1"))
        expectEqual(TerminalScripts.writeOutcome("focused"), .unexpected("focused"))
        expectEqual(TerminalScripts.writeOutcome("sent\n"), .unexpected("sent\n"))
        expectEqual(TerminalScripts.writeOutcome(""), .unexpected(""))

        expectEqual(TerminalScripts.frontState("not running"), .notRunning)
        expectEqual(TerminalScripts.frontState("not frontmost"), .notFrontmost)
        expectEqual(TerminalScripts.frontState("front\n/dev/ttys007\n✳ Fix retries"), .front(tty: "/dev/ttys007", windowTitle: "✳ Fix retries"))
        expectEqual(TerminalScripts.frontState("front\n/dev/ttys007\n"), .front(tty: "/dev/ttys007", windowTitle: ""))
        expectEqual(TerminalScripts.frontState("front\n/dev/ttys007\ntwo\nlines"), .front(tty: "/dev/ttys007", windowTitle: "two\nlines"))
        expectEqual(TerminalScripts.frontState("front\n/dev/ttys007"), .unexpected)
        expectEqual(TerminalScripts.frontState(""), .unexpected)
    }

    suite("TerminalScripts: on the session only with the tty and the focused window") {
        let front = TerminalScripts.FrontState.front(tty: "/dev/ttys007", windowTitle: "✳ T")
        expect(TerminalScripts.isOnSession(front, tty: "/dev/ttys007", focusedWindowTitle: "✳ T"), "all agree")
        expect(!TerminalScripts.isOnSession(front, tty: "/dev/ttys008", focusedWindowTitle: "✳ T"), "another tab")
        expect(!TerminalScripts.isOnSession(front, tty: "/dev/ttys007", focusedWindowTitle: "Settings"), "another window has focus")
        expect(!TerminalScripts.isOnSession(front, tty: "/dev/ttys007", focusedWindowTitle: nil), "no focused window")
        expect(!TerminalScripts.isOnSession(.notFrontmost, tty: "/dev/ttys007", focusedWindowTitle: "✳ T"), "not frontmost")
        expect(!TerminalScripts.isOnSession(.unexpected, tty: "/dev/ttys007", focusedWindowTitle: "✳ T"), "unexpected")
    }

    suite("TerminalScripts: AppleScript errors") {
        expectEqual(TerminalScripts.ScriptError(code: -1743), .notPermitted)
        expectEqual(TerminalScripts.ScriptError(code: -600), .notRunning)
        expectEqual(TerminalScripts.ScriptError(code: -1712), .timedOut)
        expectEqual(TerminalScripts.ScriptError(code: -1728), .other(-1728))
    }
}
