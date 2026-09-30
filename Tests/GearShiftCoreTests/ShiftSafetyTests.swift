import Foundation
@testable import GearShiftCore

func runShiftSafetyTests() {
    suite("ShiftTarget: resolves only a real, unique title of a live session") {
        let a = sessionRecord("a")
        let b = sessionRecord("b")
        let live = [a, b]
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["a": "Shiftcc app", "b": "Other"], liveSessions: live), .success("Shiftcc app"))
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["a": "  Padded  "], liveSessions: live), .success("Padded"))
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["a": "Same", "b": "Same"], liveSessions: live), .failure(.ambiguousTitle("Same")))
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["a": "Same", "b": " Same"], liveSessions: live), .failure(.ambiguousTitle("Same")))
        // A dead session's leftover title doesn't make a live one ambiguous.
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["a": "Same", "gone": "Same"], liveSessions: live), .success("Same"))
        expectEqual(ShiftTarget.resolve(sessionId: "gone", titles: ["gone": "Old"], liveSessions: live), .failure(.sessionGone))
    }

    suite("ShiftTarget: an untitled session is looked for as Claude Code only while it's the only one") {
        let a = sessionRecord("a")
        let b = sessionRecord("b")
        let c = sessionRecord("c")
        // No untitled session: titles as usual.
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["a": "One", "b": "Two"], liveSessions: [a, b]), .success("One"))
        // One: its tab shows Claude Code's default title.
        expectEqual(ShiftTarget.untitledTabTitle, "Claude Code")
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["b": "Other"], liveSessions: [a, b]), .success("Claude Code"))
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["a": "   ", "b": "Other"], liveSessions: [a, b]), .success("Claude Code"))
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: [:], liveSessions: [a]), .success("Claude Code"))
        // An untitled session that has ended doesn't count.
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["b": "Other", "gone": " "], liveSessions: [a, b]), .success("Claude Code"))
        // Two: both tabs would read Claude Code.
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["c": "Other"], liveSessions: [a, b, c]), .failure(.severalUntitled))
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["b": " "], liveSessions: [a, b]), .failure(.severalUntitled))
        // A titled session is still found while two others are untitled.
        expectEqual(ShiftTarget.resolve(sessionId: "c", titles: ["c": "Other"], liveSessions: [a, b, c]), .success("Other"))
        // A session renamed "Claude Code" would share the untitled one's tab title.
        expectEqual(ShiftTarget.resolve(sessionId: "a", titles: ["b": "Claude Code"], liveSessions: [a, b]), .failure(.ambiguousTitle("Claude Code")))
        expectEqual(ShiftTarget.resolve(sessionId: "b", titles: ["b": "Claude Code"], liveSessions: [a, b]), .failure(.ambiguousTitle("Claude Code")))
    }

    suite("ShiftRefusal: messages") {
        expectEqual(ShiftRefusal.severalUntitled.description, "two connected sessions have no title: /rename one (e.g. /rename backend)")
        expectEqual(ShiftRefusal.awaitingUser.description, "Claude is waiting for you in that session: answer it first")
        expectEqual(ShiftRefusal.working.description, "Claude is working in that session: wait until it's idle")
        expectEqual(ShiftRefusal.ambiguousTitle("X").description, "two sessions are named X: /rename one")
        expectEqual(ShiftRefusal.notConfirmed("/model").description, "couldn't confirm /model in that session")
        expectEqual(
            ShiftRefusal.notConfirmedUntitled("/model").description,
            "couldn't confirm /model in that session: it may have gone to another \"Claude Code\" session. /rename this one (e.g. /rename backend)")
        // Which one a shift reports depends on how the tab was found.
        expectEqual(ShiftRefusal.unconfirmed("/model", targetTitle: "Claude Code"), .notConfirmedUntitled("/model"))
        expectEqual(ShiftRefusal.unconfirmed("/model", targetTitle: "Shiftcc app"), .notConfirmed("/model"))
        let failure = ShiftFailure(
            reason: ShiftRefusal.unconfirmed("/model", targetTitle: "Claude Code").description,
            commands: [ShiftCommand(name: "/model", args: "opus")], confirmed: 0, submittedUnconfirmed: true)
        expect(failure.description.contains("another \"Claude Code\" session"), "the shift's hint warns about misdelivery")
        expect(failure.isGearUnknown, "sent somewhere: the gear is unknown")
    }

    suite("ShiftReadiness: idle glyph and transcript") {
        let idle = [Fixture.assistantText(messageId: "m1")]
        let waiting = [Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1")]
        expectEqual(ShiftReadiness.refusal(windowTitle: "✳ T", transcriptLines: idle), nil)
        expectEqual(ShiftReadiness.refusal(windowTitle: nil, transcriptLines: idle), nil)
        expectEqual(ShiftReadiness.refusal(windowTitle: "✳ T", transcriptLines: waiting), .awaitingUser)
        expectEqual(ShiftReadiness.refusal(windowTitle: nil, transcriptLines: waiting), .awaitingUser)
        expectEqual(ShiftReadiness.refusal(windowTitle: "◐ T", transcriptLines: idle), .working)
        expectEqual(ShiftReadiness.refusal(windowTitle: "⠋ T", transcriptLines: idle), .working)
        // Running a tool: the spinner says working, whatever the transcript says.
        expectEqual(ShiftReadiness.refusal(windowTitle: "◑ T", transcriptLines: waiting), .working)
        expectEqual(ShiftReadiness.refusal(windowTitle: "T", transcriptLines: idle), .working)
    }

    suite("KeyChunks") {
        let one = KeyChunks.chunks(of: "/model opus", charactersPerEvent: 1, maxUnitsPerEvent: 20)
        expectEqual(one.count, 11)
        expectEqual(one.map { String(decoding: $0, as: UTF16.self) }.joined(), "/model opus")
        expect(one.allSatisfy { $0.count == 1 }, "one unit each")

        let emoji = KeyChunks.chunks(of: "a😀b", charactersPerEvent: 1, maxUnitsPerEvent: 20)
        expectEqual(emoji.map(\.count), [1, 2, 1])  // a surrogate pair stays in one event

        let grouped = KeyChunks.chunks(of: "abcdefg", charactersPerEvent: 3, maxUnitsPerEvent: 20)
        expectEqual(grouped.map { String(decoding: $0, as: UTF16.self) }, ["abc", "def", "g"])
        let capped = KeyChunks.chunks(of: "abcdef", charactersPerEvent: 10, maxUnitsPerEvent: 4)
        expectEqual(capped.map { String(decoding: $0, as: UTF16.self) }, ["abcd", "ef"])
        let wide = KeyChunks.chunks(of: "😀😀😀", charactersPerEvent: 10, maxUnitsPerEvent: 5)
        expectEqual(wide.map(\.count), [4, 2])

        expectEqual(KeyChunks.chunks(of: "", charactersPerEvent: 1, maxUnitsPerEvent: 20), [])
        expect(KeyChunks.chunks(of: "abc", charactersPerEvent: 0, maxUnitsPerEvent: 20).allSatisfy { !$0.isEmpty }, "no empty chunks")
        expectEqual(KeyChunks.chunks(of: "abc", charactersPerEvent: 0, maxUnitsPerEvent: 20).count, 3)
    }

    suite("ShiftFailure: honest partial results") {
        let commands = [ShiftCommand(name: "/model", args: "opus"), ShiftCommand(name: "/effort", args: "max")]
        let before = ShiftFailure(reason: ShiftRefusal.working.description, commands: commands, confirmed: 0)
        expectEqual(before.description, "Claude is working in that session: wait until it's idle")
        expect(!before.isGearUnknown, "nothing was sent: the gear didn't change")

        let unsent = ShiftFailure(reason: "Warp lost focus", commands: commands, confirmed: 0, typedUnsent: true)
        expectEqual(unsent.description, "Warp lost focus: \"/model opus\" is left unsent in its input")
        expect(!unsent.isGearUnknown, "typed but not submitted")

        let unconfirmed = ShiftFailure(reason: ShiftRefusal.notConfirmed("/model").description, commands: commands, confirmed: 0, submittedUnconfirmed: true)
        expectEqual(unconfirmed.description, "couldn't confirm /model in that session")
        expect(unconfirmed.isGearUnknown, "Return was pressed: the model may have changed")

        let half = ShiftFailure(reason: ShiftRefusal.working.description, commands: commands, confirmed: 1)
        expectEqual(half.description, "model set, effort not: shift again")
        expect(half.isGearUnknown, "half a gear")

        let halfUnsent = ShiftFailure(reason: "x", commands: commands, confirmed: 1, typedUnsent: true)
        expectEqual(halfUnsent.description, "model set, effort not: shift again (\"/effort max\" is left unsent in its input)")
    }

    suite("SessionSelection") {
        let old = sessionRecord("old", registeredAt: "2026-09-30T09:00:00.000Z")
        let mid = sessionRecord("mid", registeredAt: "2026-09-30T09:00:00.250Z")
        let new = sessionRecord("new", registeredAt: "2026-09-30T09:00:00.500Z")

        // First poll: the newest is selected.
        var result = SessionSelection.update(selected: nil, newestSeen: nil, sessions: [mid, old])
        expectEqual(result, SessionSelection.Result(selected: "mid", newestSeen: mid.registeredAt, connected: nil))

        // A new registration from another session doesn't steal the selection; it's announced.
        result = SessionSelection.update(selected: "mid", newestSeen: mid.registeredAt, sessions: [new, mid, old])
        expectEqual(result, SessionSelection.Result(selected: "mid", newestSeen: new.registeredAt, connected: "new"))

        // Nothing new: nothing changes.
        result = SessionSelection.update(selected: "mid", newestSeen: new.registeredAt, sessions: [new, mid, old])
        expectEqual(result, SessionSelection.Result(selected: "mid", newestSeen: new.registeredAt, connected: nil))

        // A fresh /gearshift in the selected session keeps it selected, quietly.
        let midAgain = sessionRecord("mid", registeredAt: "2026-09-30T09:00:01Z")
        result = SessionSelection.update(selected: "mid", newestSeen: new.registeredAt, sessions: [midAgain, new, old])
        expectEqual(result, SessionSelection.Result(selected: "mid", newestSeen: midAgain.registeredAt, connected: nil))

        // The selected session ended: the newest remaining one is selected.
        result = SessionSelection.update(selected: "gone", newestSeen: new.registeredAt, sessions: [new, old])
        expectEqual(result, SessionSelection.Result(selected: "new", newestSeen: new.registeredAt, connected: nil))

        // Nothing selected (e.g. every session had ended) and a new one registers: select it.
        result = SessionSelection.update(selected: nil, newestSeen: mid.registeredAt, sessions: [new])
        expectEqual(result, SessionSelection.Result(selected: "new", newestSeen: new.registeredAt, connected: nil))

        result = SessionSelection.update(selected: "old", newestSeen: new.registeredAt, sessions: [])
        expectEqual(result, SessionSelection.Result(selected: nil, newestSeen: new.registeredAt, connected: nil))
    }
}
