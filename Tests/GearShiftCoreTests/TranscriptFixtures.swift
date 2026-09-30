import Foundation

/// Transcript lines shaped like Claude Code 2.1.282's `~/.claude/projects/*/<id>.jsonl` (checked on
/// real files, 2026-09-30); only the fields GearShift reads, plus a few of the usual extras.
enum Fixture {
    static func assistantText(messageId: String, text: String = "Done.", sidechain: Bool = false, model: String = "claude-opus-5-5") -> String {
        #"{"parentUuid":"p","isSidechain":\#(sidechain),"type":"assistant","message":{"model":"\#(model)","id":"\#(messageId)","type":"message","role":"assistant","content":[{"type":"text","text":"\#(text)"}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":3,"output_tokens":5}},"requestId":"req_1","uuid":"u-\#(messageId)-text","timestamp":"2026-09-30T10:00:00.000Z","sessionId":"s1","version":"2.1.282"}"#
    }

    static func assistantThinking(messageId: String) -> String {
        #"{"parentUuid":"p","isSidechain":false,"type":"assistant","message":{"model":"claude-opus-5-5","id":"\#(messageId)","type":"message","role":"assistant","content":[{"type":"thinking","thinking":"hmm","signature":"sig"}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":3,"output_tokens":5}},"requestId":"req_1","uuid":"u-\#(messageId)-thinking","timestamp":"2026-09-30T10:00:00.000Z","sessionId":"s1","version":"2.1.282"}"#
    }

    static func assistantToolUse(messageId: String, toolUseId: String, name: String = "Bash", sidechain: Bool = false) -> String {
        #"{"parentUuid":"p","isSidechain":\#(sidechain),"type":"assistant","message":{"model":"claude-opus-5-5","id":"\#(messageId)","type":"message","role":"assistant","content":[{"type":"tool_use","id":"\#(toolUseId)","name":"\#(name)","input":{"command":"ls"},"caller":{"type":"direct"}}],"stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":3,"output_tokens":5}},"requestId":"req_1","uuid":"u-\#(toolUseId)","timestamp":"2026-09-30T10:00:00.000Z","sessionId":"s1","version":"2.1.282"}"#
    }

    static func toolResult(toolUseId: String, isError: Bool = false, sidechain: Bool = false) -> String {
        let error = isError ? #","is_error":true"# : ""
        return #"{"parentUuid":"u-\#(toolUseId)","isSidechain":\#(sidechain),"promptId":"pr1","type":"user","message":{"role":"user","content":[{"tool_use_id":"\#(toolUseId)","type":"tool_result","content":[{"type":"text","text":"ok"}]\#(error)}]},"uuid":"r-\#(toolUseId)","timestamp":"2026-09-30T10:00:01.000Z","toolUseResult":{"stdout":"ok"},"sourceToolAssistantUUID":"u-\#(toolUseId)","sessionId":"s1","version":"2.1.282"}"#
    }

    static func userPrompt(_ text: String) -> String {
        #"{"parentUuid":"p","isSidechain":false,"promptId":"pr2","type":"user","message":{"role":"user","content":"\#(text)"},"uuid":"up","timestamp":"2026-09-30T10:00:02.000Z","sessionId":"s1","version":"2.1.282"}"#
    }

    static let attachment = #"{"parentUuid":"p","isSidechain":false,"type":"attachment","attachment":{"type":"todo_reminder"},"uuid":"ua","timestamp":"2026-09-30T10:00:02.000Z","sessionId":"s1"}"#
    static let aiTitle = #"{"type":"ai-title","aiTitle":"Shiftcc app","sessionId":"s1"}"#

    /// The command record: `<command-name>` and `<command-args>`, indented as Claude Code writes them.
    static func commandContent(_ name: String, args: String) -> String {
        #"<command-name>/\#(name)</command-name>\n            <command-message>\#(name)</command-message>\n            <command-args>\#(args)</command-args>"#
    }

    /// Current shape (2.1.276+): a `system` line with subtype `local_command` and top-level `content`.
    static func systemCommand(_ name: String, args: String, sidechain: Bool = false) -> String {
        #"{"parentUuid":"p","isSidechain":\#(sidechain),"type":"system","subtype":"local_command","content":"\#(commandContent(name, args: args))","level":"info","timestamp":"2026-09-30T10:00:03.000Z","uuid":"sc","isMeta":false,"sessionId":"s1","version":"2.1.282"}"#
    }

    static func systemStdout(_ text: String) -> String {
        #"{"parentUuid":"sc","isSidechain":false,"type":"system","subtype":"local_command","content":"<local-command-stdout>\#(text)</local-command-stdout>","level":"info","timestamp":"2026-09-30T10:00:03.000Z","uuid":"so","isMeta":false,"sessionId":"s1","version":"2.1.282","commandRun":{"command":"model","args":"opus"}}"#
    }

    /// `/model`'s output as 2.1.280–2.1.282 write it (seen on real files, 2026-09-30).
    static func systemSetModel(_ name: String) -> String {
        systemStdout("Set model to `\(name)` and saved as your default for new sessions with `high` effort")
    }

    /// `/model`'s output in 2.1.111: a user message, the name bold with ANSI codes.
    static func userSetModel(_ name: String) -> String {
        #"{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":"<local-command-stdout>Set model to \u001b[1m\#(name)\u001b[22m with \u001b[1mmedium\u001b[22m effort</local-command-stdout>"},"uuid":"um","timestamp":"2026-09-09T19:49:21.506Z","cwd":"/x","sessionId":"s1","version":"2.1.111","gitBranch":"HEAD"}"#
    }

    /// `{"type":"last-prompt",…}`, as Claude Code writes after each prompt (JSON-escaped text).
    static func lastPrompt(_ escapedText: String) -> String {
        #"{"type":"last-prompt","lastPrompt":"\#(escapedText)","leafUuid":"l1","sessionId":"s1"}"#
    }

    /// A user line carrying the git branch, as every main-thread line does.
    static func userOnBranch(_ branch: String, text: String = "hi") -> String {
        #"{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":"\#(text)"},"uuid":"ub","timestamp":"2026-09-30T10:00:02.000Z","cwd":"/x","sessionId":"s1","version":"2.1.282","gitBranch":"\#(branch)"}"#
    }

    /// A message Claude Code made up itself (e.g. after an API error): not a real model.
    static let syntheticAssistant = #"{"parentUuid":"p","isSidechain":false,"type":"assistant","uuid":"syn","timestamp":"2026-09-09T19:59:12.704Z","message":{"id":"x","container":null,"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence","stop_sequence":"","type":"message","usage":{"input_tokens":0,"output_tokens":0},"content":[{"type":"text","text":"API Error"}]},"isApiErrorMessage":true,"sessionId":"s1","gitBranch":"main"}"#

    // Turn boundaries (shapes checked on real 2.1.x transcripts, 2026-09-30).

    /// An assistant line with any `stop_reason` (`nil` writes `null`: a message that was cut off).
    static func assistant(messageId: String, stopReason: String?, sidechain: Bool = false) -> String {
        let reason = stopReason.map { "\"\($0)\"" } ?? "null"
        return #"{"parentUuid":"p","isSidechain":\#(sidechain),"type":"assistant","message":{"model":"claude-opus-5-5","id":"\#(messageId)","type":"message","role":"assistant","content":[{"type":"text","text":"x"}],"stop_reason":\#(reason),"stop_sequence":null,"usage":{"input_tokens":3,"output_tokens":5}},"uuid":"ua-\#(messageId)","timestamp":"2026-09-30T10:00:00.000Z","sessionId":"s1","version":"2.1.282"}"#
    }

    static let stopHookSummary = #"{"parentUuid":"p","isSidechain":false,"type":"system","subtype":"stop_hook_summary","hookCount":1,"hookInfos":[],"hookErrors":[],"preventedContinuation":false,"stopReason":"","hasOutput":false,"level":"suggestion","timestamp":"2026-09-30T10:00:04.000Z","uuid":"sh","sessionId":"s1"}"#
    static let turnDuration = #"{"parentUuid":"p","isSidechain":false,"type":"system","subtype":"turn_duration","durationMs":5123,"timestamp":"2026-09-30T10:00:04.000Z","uuid":"td","isMeta":false,"sessionId":"s1"}"#
    static let awaySummary = #"{"parentUuid":"p","isSidechain":false,"type":"system","subtype":"away_summary","content":"x","timestamp":"2026-09-30T10:00:05.000Z","uuid":"as","sessionId":"s1"}"#

    /// Esc: a text block, alone in its line (`[Request interrupted by user for tool use]` too).
    static func interruption(forToolUse: Bool = false) -> String {
        let text = forToolUse ? "[Request interrupted by user for tool use]" : "[Request interrupted by user]"
        return #"{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"\#(text)"}]},"uuid":"ui","timestamp":"2026-09-30T10:00:05.000Z","sessionId":"s1"}"#
    }

    /// A user line whose string content is `content` (JSON-escaped), meta or not.
    static func userString(_ content: String, isMeta: Bool = false) -> String {
        #"{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":"\#(content)"},"isMeta":\#(isMeta),"uuid":"us","timestamp":"2026-09-30T10:00:06.000Z","sessionId":"s1"}"#
    }

    /// A prompt with an image: text and image blocks.
    static let userPromptWithImage = #"{"parentUuid":"p","isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"look"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"AA=="}}]},"uuid":"uimg","timestamp":"2026-09-30T10:00:06.000Z","sessionId":"s1"}"#

    /// After `/compact`: the summary, as a user line flagged `isCompactSummary`.
    static let compactSummary = #"{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"This session is being continued from a previous conversation."},"isVisibleInTranscriptOnly":true,"isCompactSummary":true,"uuid":"cs","timestamp":"2026-09-30T10:00:07.000Z","sessionId":"s1"}"#
    static let compactBoundary = #"{"parentUuid":null,"isSidechain":false,"type":"system","subtype":"compact_boundary","content":"Conversation compacted","compactMetadata":{"trigger":"manual"},"uuid":"cb","timestamp":"2026-09-30T10:00:07.000Z","sessionId":"s1"}"#

    /// Older shape (also seen in 2.1.278): a `user` message whose content is the record string.
    static func userCommand(_ name: String, args: String) -> String {
        #"{"parentUuid":"p","isSidechain":false,"promptId":"pr3","type":"user","message":{"role":"user","content":"\#(commandContent(name, args: args))"},"uuid":"uc","timestamp":"2026-09-30T10:00:03.000Z","sessionId":"s1","version":"2.1.278"}"#
    }
}
