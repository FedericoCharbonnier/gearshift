import Foundation
@testable import GearShiftCore

func ttyRecord(_ id: String, terminal: TerminalKind?, tty: String? = nil, termProgram: String? = nil) -> SessionRecord {
    SessionRecord(
        sessionId: id, cwd: "/Users/me/dev/\(id)", transcriptPath: "/t/\(id).jsonl", claudePid: 100,
        registeredAt: JSONLine.date("2026-09-30T10:00:00Z")!, terminal: terminal, tty: tty, termProgram: termProgram)
}

func runTerminalKindTests() {
    suite("TerminalKind: from TERM_PROGRAM, as register.sh maps it") {
        expectEqual(TerminalKind.from(termProgram: "WarpTerminal"), .warp)
        expectEqual(TerminalKind.from(termProgram: "iTerm.app"), .iterm)
        expectEqual(TerminalKind.from(termProgram: "Apple_Terminal"), .terminal)
        for other in ["vscode", "tmux", "ghostty", "", "iterm.app", "Terminal"] {
            expectEqual(TerminalKind.from(termProgram: other), .other)
        }
        expectEqual(TerminalKind.from(termProgram: nil), .other)
        expectEqual(TerminalKind(recorded: "iterm"), .iterm)
        expectEqual(TerminalKind(recorded: "kitty"), .other)
    }

    suite("TerminalKind: names, apps, and how tabs are found") {
        expectEqual(TerminalKind.allCases.map(\.displayName), ["Warp", "iTerm", "Terminal", "other"])
        expectEqual(TerminalKind.warp.bundleIdentifier, "dev.warp.Warp-Stable")
        expectEqual(TerminalKind.iterm.bundleIdentifier, "com.googlecode.iterm2")
        expectEqual(TerminalKind.terminal.bundleIdentifier, "com.apple.Terminal")
        expectEqual(TerminalKind.other.bundleIdentifier, nil)
        expectEqual(TerminalKind.allCases.filter(\.isFoundByTTY), [.iterm, .terminal])
    }

    suite("TTYPath: macOS pseudo-terminals only") {
        for good in ["/dev/ttys0", "/dev/ttys007", "/dev/ttys12345"] {
            expect(TTYPath.isValid(good), good)
        }
        for bad in ["", "ttys007", "/dev/ttys", "/dev/ttys123456", "/dev/tty", "/dev/console", "/dev/ttyp1", "/dev/ttys00a",
                    "/dev/ttys007\n", "/dev/ttys007\" & quit", "/dev/ttys٣", "/dev/../dev/ttys1"] {
            expect(!TTYPath.isValid(bad), "rejects [\(bad)]")
        }
    }

    suite("TerminalStrategy: title for Warp, tty for iTerm2 and Terminal") {
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: nil)), .success(.warpTitle))
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: nil, tty: "/dev/ttys001")), .success(.warpTitle))
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: .warp, tty: "/dev/ttys001")), .success(.warpTitle))
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: .iterm, tty: "/dev/ttys001")), .success(.tty(.iterm, "/dev/ttys001")))
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: .terminal, tty: "/dev/ttys002")), .success(.tty(.terminal, "/dev/ttys002")))
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: .terminal)), .failure(.unknownTTY("Terminal")))
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: .iterm, tty: "bogus")), .failure(.unknownTTY("iTerm")))
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: .other, termProgram: "vscode")), .failure(.unsupportedTerminal("vscode")))
        expectEqual(TerminalStrategy.location(of: ttyRecord("a", terminal: .other)), .failure(.unsupportedTerminal("another terminal")))
        expectEqual(
            ShiftRefusal.unsupportedTerminal("vscode").description,
            "GearShift supports Warp, iTerm2 and Terminal; this session runs in vscode")
        expectEqual(ShiftRefusal.unknownTTY("iTerm").description, "couldn't tell which iTerm tab that session is in: run /gearshift in it again")
        expect(TerminalStrategy.isFoundByTTY(ttyRecord("a", terminal: .iterm, tty: "/dev/ttys001")), "iTerm with a tty")
        expect(!TerminalStrategy.isFoundByTTY(ttyRecord("a", terminal: .iterm)), "iTerm without one")
        expect(!TerminalStrategy.isFoundByTTY(ttyRecord("a", terminal: nil, tty: "/dev/ttys001")), "an old record")
    }

    suite("ShiftTarget.resolveTarget: by terminal") {
        let warp = sessionRecord("w")
        let iterm = ttyRecord("i", terminal: .iterm, tty: "/dev/ttys003")
        let terminal = ttyRecord("t", terminal: .terminal, tty: "/dev/ttys004")
        let live = [warp, iterm, terminal]
        let titles = ["w": "Same", "i": "Same", "t": "Same"]
        expectEqual(ShiftTarget.resolveTarget(sessionId: "w", titles: titles, liveSessions: live), .success(.warpTab(title: "Same")))
        expectEqual(ShiftTarget.resolveTarget(sessionId: "i", titles: titles, liveSessions: live), .success(.ttyTab(.iterm, tty: "/dev/ttys003")))
        expectEqual(ShiftTarget.resolveTarget(sessionId: "t", titles: [:], liveSessions: live), .success(.ttyTab(.terminal, tty: "/dev/ttys004")))
        expectEqual(ShiftTarget.resolveTarget(sessionId: "gone", titles: titles, liveSessions: live), .failure(.sessionGone))
        let vscode = ttyRecord("v", terminal: .other, tty: "/dev/ttys009", termProgram: "vscode")
        expectEqual(ShiftTarget.resolveTarget(sessionId: "v", titles: [:], liveSessions: live + [vscode]), .failure(.unsupportedTerminal("vscode")))
        let noTTY = ttyRecord("n", terminal: .terminal)
        expectEqual(ShiftTarget.resolveTarget(sessionId: "n", titles: [:], liveSessions: live + [noTTY]), .failure(.unknownTTY("Terminal")))
    }

    suite("ShiftTarget: tty sessions don't make Warp titles ambiguous, but other sessions do") {
        let warp = sessionRecord("w")
        let iterm = ttyRecord("i", terminal: .iterm, tty: "/dev/ttys003")
        let untitledTerminal = ttyRecord("t", terminal: .terminal, tty: "/dev/ttys004")
        // Titles and untitled sessions in iTerm2 or Terminal can't show up as Warp tabs.
        expectEqual(ShiftTarget.resolve(sessionId: "w", titles: ["w": "Same", "i": "Same"], liveSessions: [warp, iterm]), .success("Same"))
        expectEqual(ShiftTarget.resolve(sessionId: "w", titles: [:], liveSessions: [warp, untitledTerminal]), .success("Claude Code"))
        // A session in another terminal (tmux in Warp, say) might.
        let tmux = ttyRecord("x", terminal: .other, tty: "/dev/ttys005", termProgram: "tmux")
        expectEqual(ShiftTarget.resolve(sessionId: "w", titles: ["w": "Same", "x": "Same"], liveSessions: [warp, tmux]), .failure(.ambiguousTitle("Same")))
        // So might an iTerm2 session whose tty wasn't recorded.
        let itermNoTTY = ttyRecord("n", terminal: .iterm)
        expectEqual(ShiftTarget.resolve(sessionId: "w", titles: [:], liveSessions: [warp, itermNoTTY]), .failure(.severalUntitled))
    }

    suite("ShiftTarget: two live sessions on one tty") {
        let first = ttyRecord("a", terminal: .terminal, tty: "/dev/ttys004")
        let second = ttyRecord("b", terminal: .terminal, tty: "/dev/ttys004")
        let other = ttyRecord("c", terminal: .terminal, tty: "/dev/ttys005")
        expectEqual(ShiftTarget.resolveTarget(sessionId: "a", titles: [:], liveSessions: [first, second, other]), .failure(.sharedTTY))
        expectEqual(ShiftTarget.resolveTarget(sessionId: "c", titles: [:], liveSessions: [first, second, other]), .success(.ttyTab(.terminal, tty: "/dev/ttys005")))
        // Whatever terminal the other one says it's in.
        let oldWarp = ttyRecord("w", terminal: nil, tty: "/dev/ttys005")
        expectEqual(ShiftTarget.resolveTarget(sessionId: "c", titles: [:], liveSessions: [other, oldWarp]), .failure(.sharedTTY))
        expectEqual(ShiftRefusal.sharedTTY.description, "two connected sessions share one tab: run /gearshift in the one to shift")
    }

    suite("ShiftReadiness without a title: the transcript alone") {
        let idle = [Fixture.userPrompt("hi"), Fixture.assistantText(messageId: "m1"), Fixture.turnDuration]
        expectEqual(ShiftReadiness.refusal(transcriptLines: idle), nil)
        expectEqual(ShiftReadiness.refusal(transcriptLines: []), nil)
        expectEqual(ShiftReadiness.refusal(transcriptLines: idle + [Fixture.userPrompt("go")]), .working)
        expectEqual(ShiftReadiness.refusal(transcriptLines: [Fixture.userPrompt("go"), Fixture.toolResult(toolUseId: "t0")]), .working)
        expectEqual(
            ShiftReadiness.refusal(transcriptLines: [Fixture.userPrompt("go"), Fixture.assistantToolUse(messageId: "m2", toolUseId: "t1")]),
            .toolPending)
        expectEqual(
            ShiftRefusal.toolPending.description,
            "Claude is running a tool or waiting for you in that session: wait, or answer it first")
        // Warp's rule is unchanged: an idle glyph with a pending tool call is a prompt for the user.
        expectEqual(
            ShiftReadiness.refusal(windowTitle: "✳ T", transcriptLines: [Fixture.assistantToolUse(messageId: "m2", toolUseId: "t1")]),
            .awaitingUser)
        expectEqual(ShiftReadiness.refusal(windowTitle: "✳ T", transcriptLines: [Fixture.userPrompt("go")]), nil)
    }
}
