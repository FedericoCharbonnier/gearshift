import Foundation
@testable import GearShiftCore

func runSessionInfoTests() {
    func transcript(_ lines: [String]) throws -> URL {
        let url = makeTemporaryDirectory().appendingPathComponent("s1.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func info(_ lines: [String]) throws -> SessionInfo {
        SessionInfoTracker(url: try transcript(lines)).current()
    }
    let aiTitle = #"{"type":"ai-title","aiTitle":"Shiftcc app","sessionId":"s1"}"#

    suite("SessionInfo: last prompt") {
        expectEqual(try info([Fixture.lastPrompt("first"), Fixture.lastPrompt("second")]).lastPrompt, "second")
        // Collapsed to one line.
        expectEqual(try info([Fixture.lastPrompt(#"fix the\n\n  build\tplease "#)]).lastPrompt, "fix the build please")
        // Lines with only a leafUuid are skipped.
        let leafOnly = #"{"type":"last-prompt","leafUuid":"l2","sessionId":"s1"}"#
        expectEqual(try info([Fixture.lastPrompt("kept"), leafOnly]).lastPrompt, "kept")
        expectEqual(try info([Fixture.lastPrompt("   ")]).lastPrompt, nil)
        // The words "last-prompt" in a user message aren't a last-prompt line.
        expectEqual(try info([Fixture.lastPrompt("real"), Fixture.userPrompt(#"what's a \"last-prompt\" line"#)]).lastPrompt, "real")
        expectEqual(try info([Fixture.userPrompt("hi")]).lastPrompt, nil)
    }

    suite("SessionInfo.singleLine") {
        expectEqual(SessionInfo.singleLine("a\nb\r\nc"), "a b c")
        expectEqual(SessionInfo.singleLine(" \n\t "), nil)
        expectEqual(SessionInfo.singleLine("abcdefgh", maxLength: 5), "abcd…")
        expectEqual(SessionInfo.singleLine("abcde", maxLength: 5), "abcde")
    }

    suite("SessionInfo: git branch") {
        expectEqual(try info([Fixture.userOnBranch("main"), Fixture.userOnBranch("feature/x")]).gitBranch, "feature/x")
        // Empty values don't hide an earlier branch; lines without one are ignored.
        expectEqual(try info([Fixture.userOnBranch("main"), Fixture.userOnBranch(""), aiTitle]).gitBranch, "main")
        expectEqual(try info([aiTitle]).gitBranch, nil)
    }

    suite("SessionInfo: model from the last assistant message") {
        expectEqual(try info([Fixture.assistantText(messageId: "m1", model: "claude-sonnet-5"),
                              Fixture.assistantText(messageId: "m2", model: "claude-opus-5-5")]).model, "claude-opus-5-5")
        // <synthetic> and empty models are skipped, and so are subagents'.
        expectEqual(try info([Fixture.assistantText(messageId: "m1", model: "claude-opus-5-5"), Fixture.syntheticAssistant]).model, "claude-opus-5-5")
        expectEqual(try info([Fixture.assistantText(messageId: "m1", model: "claude-opus-5-5"),
                              Fixture.assistantText(messageId: "m2", model: "")]).model, "claude-opus-5-5")
        expectEqual(try info([Fixture.assistantText(messageId: "m1", model: "claude-opus-5-5"),
                              Fixture.assistantText(messageId: "m2", sidechain: true, model: "claude-haiku-4-5-20251001")]).model, "claude-opus-5-5")
        // Other lines with a "model" key (e.g. thinking_drop attachments) aren't answers.
        let attachment = #"{"parentUuid":"p","isSidechain":false,"attachment":{"type":"thinking_drop","model":"claude-opus-5-5[1m]"},"type":"attachment","sessionId":"s1"}"#
        expectEqual(try info([Fixture.assistantText(messageId: "m1", model: "claude-sonnet-5"), attachment]).model, "claude-sonnet-5")
        expectEqual(try info([Fixture.syntheticAssistant]).model, nil)
    }

    suite("SessionInfo: a later /model wins, and a later answer wins over it") {
        let answered = Fixture.assistantText(messageId: "m1", model: "claude-opus-5-5")
        expectEqual(try info([answered, Fixture.systemCommand("model", args: "sonnet"), Fixture.systemSetModel("Sonnet 5")]).model, "Sonnet 5")
        expectEqual(try info([Fixture.systemSetModel("Sonnet 5"), Fixture.assistantText(messageId: "m2", model: "claude-sonnet-5")]).model, "claude-sonnet-5")
        // The older shape: a user message with the name in ANSI bold.
        expectEqual(try info([answered, Fixture.userSetModel("Opus 4.7 (1M context)")]).model, "Opus 4.7 (1M context)")
        // Other /model output ("Kept model as …") and other commands' output don't change it.
        expectEqual(try info([answered, Fixture.systemStdout("Kept model as `Sonnet 5`")]).model, "claude-opus-5-5")
        expectEqual(try info([answered, Fixture.systemStdout("Set effort level to max")]).model, "claude-opus-5-5")
        // The words in a user's own message aren't /model output.
        expectEqual(try info([answered, Fixture.userPrompt("Set model to haiku please")]).model, "claude-opus-5-5")
    }

    suite("SessionInfo: every field at once, title as before") {
        let lines = [
            Fixture.userOnBranch("main"),
            #"{"type":"custom-title","customTitle":"Mine","sessionId":"s1"}"#,
            Fixture.assistantText(messageId: "m1", model: "claude-opus-5-5"),
            Fixture.lastPrompt("ship it"),
            aiTitle,
        ]
        expectEqual(try info(lines), SessionInfo(title: "Mine", lastPrompt: "ship it", model: "claude-opus-5-5", gitBranch: "main"))
        expectEqual(SessionInfoTracker(url: makeTemporaryDirectory().appendingPathComponent("missing.jsonl")).current(), SessionInfo())
    }

    suite("SessionInfoTracker: appended lines update each field") {
        let url = try transcript([Fixture.userOnBranch("main"), Fixture.assistantText(messageId: "m1", model: "claude-opus-5-5")])
        let tracker = SessionInfoTracker(url: url)
        expectEqual(tracker.current(), SessionInfo(model: "claude-opus-5-5", gitBranch: "main"))

        try append(Fixture.lastPrompt("next") + "\n" + aiTitle + "\n", to: url)
        expectEqual(tracker.current(), SessionInfo(title: "Shiftcc app", lastPrompt: "next", model: "claude-opus-5-5", gitBranch: "main"))

        // A /model in a later read beats the earlier answer's model.
        try append(Fixture.systemSetModel("Haiku 4.5") + "\n", to: url)
        expectEqual(tracker.current().model, "Haiku 4.5")
        // Later reads without those fields keep what was found before.
        try append(Fixture.attachment + "\n", to: url)
        expectEqual(tracker.current(), SessionInfo(title: "Shiftcc app", lastPrompt: "next", model: "Haiku 4.5", gitBranch: "main"))
        // A line still being written counts once it's complete JSON, and isn't counted twice.
        try append(Fixture.userOnBranch("dev"), to: url)
        expectEqual(tracker.current().gitBranch, "dev")
        try append("\n" + Fixture.attachment + "\n", to: url)
        expectEqual(tracker.current().gitBranch, "dev")
        // Replaced by a shorter file: start over.
        try (Fixture.lastPrompt("fresh") + "\n").write(to: url, atomically: true, encoding: .utf8)
        expectEqual(tracker.current(), SessionInfo(lastPrompt: "fresh"))
    }

    suite("ModelName.display") {
        expectEqual(ModelName.display("claude-opus-5-5"), "opus 5.5")
        expectEqual(ModelName.display("claude-sonnet-5"), "sonnet 5")
        expectEqual(ModelName.display("claude-haiku-4-5-20251001"), "haiku 4.5")
        expectEqual(ModelName.display("claude-fable-5-1"), "fable 5.1")
        expectEqual(ModelName.display("claude-opus-4-20250514"), "opus 4")
        expectEqual(ModelName.display("claude-3-5-sonnet-20241022"), "sonnet 3.5")
        expectEqual(ModelName.display("claude-opus-5-5[1m]"), "opus 5.5 1M")
        expectEqual(ModelName.display("opus[1m]"), "opus[1m]")
        // Names /model printed.
        expectEqual(ModelName.display("Opus 5.5 (1M context)"), "opus 5.5 1M")
        expectEqual(ModelName.display("Opus 5 (1M context) (default)"), "opus 5 1M")
        expectEqual(ModelName.display("Sonnet 4.6"), "sonnet 4.6")
        expectEqual(ModelName.display("Default (recommended)"), "default")
        // Anything else as it is.
        expectEqual(ModelName.display("opus"), "opus")
        expectEqual(ModelName.display("gpt-5-codex"), "gpt-5-codex")
        expectEqual(ModelName.display("<synthetic>"), "<synthetic>")
    }

    suite("ModelName.switched: /model output") {
        func stdout(_ text: String) -> String { "<local-command-stdout>\(text)</local-command-stdout>" }
        expectEqual(ModelName.switched(commandOutput: stdout("Set model to `Opus 5.5 (1M context)` and saved as your default for new sessions with `high` effort")), "Opus 5.5 (1M context)")
        expectEqual(ModelName.switched(commandOutput: stdout("Set model to `Sonnet 5`")), "Sonnet 5")
        expectEqual(ModelName.switched(commandOutput: stdout("Set model to \u{1B}[1mSonnet 4.6\u{1B}[22m with \u{1B}[1mhigh\u{1B}[22m effort")), "Sonnet 4.6")
        expectEqual(ModelName.switched(commandOutput: stdout("Set model to \u{1B}[1mOpus 4.7 (1M context) (default)\u{1B}[22m")), "Opus 4.7 (1M context) (default)")
        expectEqual(ModelName.switched(commandOutput: stdout("Set model to opus.")), "opus")
        expectEqual(ModelName.switched(commandOutput: stdout("Kept model as `Opus 5.5 (1M context)`")), nil)
        expectEqual(ModelName.switched(commandOutput: stdout("Set model to ")), nil)
        expectEqual(ModelName.switched(commandOutput: "Set model to opus"), nil)
    }

    suite("SessionColor: stable per nickname, else per session") {
        // FNV-1a test vectors.
        expectEqual(SessionColor.fnv1a(""), 0x811c_9dc5)
        expectEqual(SessionColor.fnv1a("a"), 0xe40c_292c)
        expectEqual(SessionColor.fnv1a("foobar"), 0xbf9c_f968)
        expectEqual(SessionColor.palette.count, 8)
        expectEqual(Set(SessionColor.palette).count, 8)
        expect(!SessionColor.palette.map { $0.lowercased() }.contains("#8affc1"), "no VFD green")
        expect(SessionColor.palette.allSatisfy { $0.range(of: "^#[0-9a-f]{6}$", options: .regularExpression) != nil }, "hex colours")

        var named = sessionRecord("s-1")
        named.nickname = "backend"
        var sameName = sessionRecord("s-2")
        sameName.nickname = "backend"
        let unnamed = sessionRecord("s-1")
        expectEqual(SessionColor.key(for: named), "backend")
        expectEqual(SessionColor.key(for: unnamed), "s-1")
        expectEqual(SessionColor.hex(for: named), SessionColor.hex(for: sameName))
        // Pinned, so a change of hash or palette order shows up here.
        expectEqual(SessionColor.index(forKey: "backend"), Int(SessionColor.fnv1a("backend") % 8))
        expectEqual(SessionColor.index(forKey: "backend"), 7)
        let indices = Set(["backend", "frontend", "infra", "docs", "api", "web", "ios", "data"].map(SessionColor.index(forKey:)))
        expect(indices.count > 3, "different names spread over the palette")
    }
}
