@testable import GearShiftCore

func runTranscriptStateTests() {
    suite("TranscriptState: idle transcripts") {
        expect(!TranscriptState.isAwaitingUser(lines: []), "empty")
        expect(!TranscriptState.isAwaitingUser(lines: [Fixture.aiTitle]), "no assistant message")
        expect(!TranscriptState.isAwaitingUser(lines: [
            Fixture.userPrompt("hi"), Fixture.assistantThinking(messageId: "m1"), Fixture.assistantText(messageId: "m1"),
        ]), "ended with text")
        expect(!TranscriptState.isAwaitingUser(lines: [
            Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1"), Fixture.toolResult(toolUseId: "t1"),
            Fixture.assistantText(messageId: "m2"), Fixture.attachment,
        ]), "tool answered, then text")
    }

    suite("TranscriptState: a tool_use without a tool_result waits for the user") {
        expect(TranscriptState.isAwaitingUser(lines: [
            Fixture.userPrompt("run it"), Fixture.assistantThinking(messageId: "m1"),
            Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1"),
        ]), "pending permission")
        expect(TranscriptState.isAwaitingUser(lines: [
            Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1", name: "AskUserQuestion"),
            Fixture.attachment, Fixture.aiTitle,
        ]), "lines that aren't messages don't resolve it")
        expect(!TranscriptState.isAwaitingUser(lines: [
            Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1"), Fixture.toolResult(toolUseId: "t1", isError: true),
        ]), "a rejected tool is answered")
    }

    suite("TranscriptState: parallel tool uses in one message") {
        let first = Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1")
        let second = Fixture.assistantToolUse(messageId: "m1", toolUseId: "t2")
        expect(TranscriptState.isAwaitingUser(lines: [first, second, Fixture.toolResult(toolUseId: "t1")]), "one of two answered")
        expect(!TranscriptState.isAwaitingUser(lines: [first, second, Fixture.toolResult(toolUseId: "t2"), Fixture.toolResult(toolUseId: "t1")]), "both answered")
    }

    suite("TranscriptState: only the last assistant message counts") {
        expect(!TranscriptState.isAwaitingUser(lines: [
            Fixture.assistantToolUse(messageId: "m1", toolUseId: "t-orphan"), Fixture.userPrompt("never mind"),
            Fixture.assistantText(messageId: "m2"),
        ]), "an old unanswered tool_use is superseded")
        expect(TranscriptState.isAwaitingUser(lines: [
            Fixture.assistantText(messageId: "m1"), Fixture.userPrompt("go"),
            Fixture.assistantToolUse(messageId: "m2", toolUseId: "t2"),
        ]), "the newest message is waiting")
        // A tool_result before the tool_use (e.g. from an earlier id reused) doesn't count.
        expect(TranscriptState.isAwaitingUser(lines: [
            Fixture.toolResult(toolUseId: "t9"), Fixture.assistantToolUse(messageId: "m9", toolUseId: "t9"),
        ]), "the result must come later")
    }

    suite("TranscriptState: sidechains and junk are ignored") {
        expect(!TranscriptState.isAwaitingUser(lines: [
            Fixture.assistantText(messageId: "m1"),
            Fixture.assistantToolUse(messageId: "m2", toolUseId: "t2", sidechain: true),
        ]), "a subagent's pending tool isn't the user's business")
        expect(TranscriptState.isAwaitingUser(lines: [
            Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1"), "not json", #"{"type":"assistant","message":"#,
        ]), "a cut or broken line is skipped")
    }

    suite("TranscriptState.isBusy: a finished turn is idle") {
        expect(!TranscriptState.isBusy(lines: []), "empty")
        expect(!TranscriptState.isBusy(lines: [Fixture.aiTitle, Fixture.lastPrompt("hi")]), "no messages")
        let ended = [
            Fixture.userPrompt("hi"), Fixture.assistantThinking(messageId: "m1"),
            Fixture.assistant(messageId: "m2", stopReason: "end_turn"), Fixture.assistantText(messageId: "m2"),
            Fixture.stopHookSummary, Fixture.turnDuration, Fixture.awaySummary, Fixture.aiTitle,
        ]
        expect(!TranscriptState.isBusy(lines: ended), "end_turn, then hooks, duration and summaries")
        expect(!TranscriptState.isBusy(lines: [Fixture.userPrompt("hi"), Fixture.assistantText(messageId: "m1")]), "end_turn alone")
        expect(!TranscriptState.isBusy(lines: [Fixture.userPrompt("hi"), Fixture.syntheticAssistant]), "Claude Code's own error message (stop_sequence)")
        expect(!TranscriptState.isBusy(lines: [Fixture.userPrompt("hi"), Fixture.assistant(messageId: "m1", stopReason: "max_tokens")]), "max_tokens")
        expect(!TranscriptState.isBusy(lines: [
            Fixture.userPrompt("hi"), Fixture.assistant(messageId: "m1", stopReason: "end_turn"), Fixture.stopHookSummary,
        ]), "no turn_duration line")
    }

    suite("TranscriptState.isBusy: a started or running turn is busy") {
        expect(TranscriptState.isBusy(lines: [Fixture.assistantText(messageId: "m0"), Fixture.turnDuration, Fixture.userPrompt("go")]), "a prompt")
        expect(TranscriptState.isBusy(lines: [Fixture.turnDuration, Fixture.userPromptWithImage]), "a prompt with an image")
        expect(TranscriptState.isBusy(lines: [Fixture.userPrompt("go"), Fixture.assistantThinking(messageId: "m1")]), "thinking before a tool call")
        expect(TranscriptState.isBusy(lines: [
            Fixture.userPrompt("go"), Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1"), Fixture.toolResult(toolUseId: "t1"),
        ]), "a tool result, the next message not written yet")
        expect(TranscriptState.isBusy(lines: [Fixture.userPrompt("go"), Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1")]), "a tool call")
        expect(TranscriptState.isBusy(lines: [Fixture.userPrompt("go"), Fixture.assistant(messageId: "m1", stopReason: nil)]), "a message without a stop_reason")
        expect(TranscriptState.isBusy(lines: [Fixture.turnDuration, Fixture.userString("<task-notification>\\n<task-id>b1</task-id></task-notification>")]), "a background task's notification starts a turn")
        expect(TranscriptState.isBusy(lines: [Fixture.turnDuration, Fixture.userString("<command-message>gearshift</command-message>\\n<command-name>/gearshift</command-name>")]), "a skill command")
        expect(TranscriptState.isBusy(lines: [Fixture.turnDuration, Fixture.userString("Base directory for this skill: /x", isMeta: true)]), "a meta prompt (a skill's body, a scheduled prompt)")
        expect(TranscriptState.isBusy(lines: [
            Fixture.userPrompt("go"), Fixture.assistant(messageId: "m1", stopReason: "refusal"),
        ]), "a refusal is retried")
        expect(TranscriptState.isBusy(lines: [
            Fixture.assistantText(messageId: "m0"), Fixture.turnDuration, Fixture.userPrompt("again"),
            Fixture.stopHookSummary, Fixture.aiTitle,
        ]), "lines that don't start or end a turn don't end it")
    }

    suite("TranscriptState.isBusy: an interruption ends the turn") {
        expect(!TranscriptState.isBusy(lines: [
            Fixture.userPrompt("go"), Fixture.assistant(messageId: "m1", stopReason: nil), Fixture.interruption(),
        ]), "Esc while streaming")
        expect(!TranscriptState.isBusy(lines: [
            Fixture.userPrompt("go"), Fixture.assistantToolUse(messageId: "m1", toolUseId: "t1"),
            Fixture.toolResult(toolUseId: "t1", isError: true), Fixture.interruption(forToolUse: true),
        ]), "Esc at a tool call")
        expect(TranscriptState.isBusy(lines: [Fixture.interruption(), Fixture.userPrompt("next")]), "the next prompt")
    }

    suite("TranscriptState.isBusy: local commands and shell input leave an idle session idle") {
        let idle = [Fixture.userPrompt("hi"), Fixture.assistantText(messageId: "m1"), Fixture.turnDuration]
        expect(!TranscriptState.isBusy(lines: idle + [Fixture.systemCommand("model", args: "opus"), Fixture.systemSetModel("Opus 5.5")]), "/model (system lines)")
        expect(!TranscriptState.isBusy(lines: idle + [
            Fixture.userString("<local-command-caveat>Caveat: …</local-command-caveat>", isMeta: true),
            Fixture.userCommand("model", args: "opus"), Fixture.userSetModel("Opus 5.5"),
        ]), "/model (older user lines)")
        expect(!TranscriptState.isBusy(lines: idle + [
            Fixture.userString("<bash-input>ls</bash-input>"), Fixture.userString("<bash-stdout>a</bash-stdout><bash-stderr></bash-stderr>"),
        ]), "! shell input")
        expect(!TranscriptState.isBusy(lines: idle + [Fixture.userString("<local-command-stderr>x</local-command-stderr>")]), "a command's error output")
        expect(!TranscriptState.isBusy(lines: idle + [Fixture.compactBoundary, Fixture.compactSummary]), "/compact")
        // …and a busy one busy: auto-compaction happens mid-turn.
        expect(TranscriptState.isBusy(lines: [Fixture.userPrompt("go"), Fixture.compactBoundary, Fixture.compactSummary]), "compaction mid-turn")
    }

    suite("TranscriptState.isBusy: subagents and junk are ignored") {
        expect(!TranscriptState.isBusy(lines: [
            Fixture.assistantText(messageId: "m1"),
            Fixture.assistant(messageId: "s1", stopReason: nil, sidechain: true),
            Fixture.toolResult(toolUseId: "st", sidechain: true),
        ]), "a subagent's lines")
        expect(!TranscriptState.isBusy(lines: [Fixture.assistantText(messageId: "m1"), "not json", #"{"type":"user","message":"#]), "a cut line")
        // The tail read may start mid-turn: the last line still decides.
        expect(TranscriptState.isBusy(lines: [Fixture.toolResult(toolUseId: "t1")]), "a tail that starts mid-turn")
    }
}
