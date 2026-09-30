import Foundation

/// What a session's transcript says about typing into it now.
///
/// Claude Code writes each block of a response as its own line, repeating `message.id`; a tool call
/// is a `tool_use` block (`id`) in an assistant line, and its answer a `tool_result` block
/// (`tool_use_id`) in a later user line. Between the two, Claude is either running the tool or
/// asking the user (permission, a question): keystrokes then could answer that prompt.
public enum TranscriptState {
    /// Whether the last assistant message has a tool call without a later result. Lines of
    /// subagents (`isSidechain`) and lines that don't parse are ignored.
    public static func isAwaitingUser(lines: [String]) -> Bool {
        var lastMessageId: String?
        var pendingToolUses: Set<String> = []
        for line in lines {
            // Most lines are neither; skip them before paying for JSON parsing.
            guard line.contains(#""assistant""#) || line.contains(#""tool_result""#),
                  let object = JSONLine.object(line),
                  object["isSidechain"] as? Bool != true,
                  let message = object["message"] as? [String: Any]
            else { continue }
            let blocks = message["content"] as? [[String: Any]] ?? []
            switch object["type"] as? String {
            case "assistant":
                let id = message["id"] as? String
                if id == nil || id != lastMessageId {
                    lastMessageId = id
                    pendingToolUses = []
                }
                for block in blocks where block["type"] as? String == "tool_use" {
                    if let toolUseId = block["id"] as? String {
                        pendingToolUses.insert(toolUseId)
                    }
                }
            case "user":
                for block in blocks where block["type"] as? String == "tool_result" {
                    if let toolUseId = block["tool_use_id"] as? String {
                        pendingToolUses.remove(toolUseId)
                    }
                }
            default:
                continue
            }
        }
        return !pendingToolUses.isEmpty
    }

    /// Whether Claude is in the middle of a turn, judged by the last main-chain line that starts,
    /// continues or ends one, for terminals whose titles GearShift doesn't read (iTerm2, Terminal).
    ///
    /// Shapes seen on Claude Code 2.1.x transcripts (2026-09-30):
    /// - A turn starts with a user prompt (string content, or text and image blocks), a skill's
    ///   `<command-message>` line, a `<task-notification>`, or a meta line injected for Claude
    ///   (a skill's body, a scheduled prompt).
    /// - It goes on through assistant lines whose `stop_reason` is `tool_use` and user
    ///   `tool_result` lines. Assistant lines are written with the message's final `stop_reason`;
    ///   `null` is a message that was cut off.
    /// - It ends with an assistant message whose `stop_reason` is `end_turn` (`stop_sequence`
    ///   for Claude Code's own error messages, or `max_tokens`), usually followed by
    ///   `system`/`stop_hook_summary` and `system`/`turn_duration`, or with a
    ///   `[Request interrupted by user…]` line when the user pressed Esc. A `refusal` is followed by
    ///   a retry, so it doesn't end the turn.
    /// - Local commands and `!` shell input leave turns alone: `system`/`local_command` lines, and
    ///   user lines starting with `<command-name>`, `<local-command-…>` or `<bash-…>` (the older
    ///   shape), as do compaction summaries and other `system` lines.
    ///
    /// Subagents' lines (`isSidechain`) and lines that don't parse are ignored. With no such line
    /// at all, nothing is going on.
    public static func isBusy(lines: [String]) -> Bool {
        var isBusy = false
        for line in lines {
            guard let object = JSONLine.object(line), object["isSidechain"] as? Bool != true,
                  let effect = turnEffect(of: object)
            else { continue }
            isBusy = effect == .continues
        }
        return isBusy
    }

    private enum TurnEffect {
        case continues
        case ends
    }

    private static let turnEndingStopReasons: Set<String> = ["end_turn", "stop_sequence", "max_tokens"]
    /// User lines that start with these don't start a turn: local commands' records and output,
    /// and `!` shell input and output.
    private static let neutralUserPrefixes = ["<command-name>", "<local-command-", "<bash-"]
    private static let interruptionPrefix = "[Request interrupted by user"

    /// What a line does to the current turn, or nil when it leaves it alone.
    private static func turnEffect(of object: [String: Any]) -> TurnEffect? {
        switch object["type"] as? String {
        case "assistant":
            let message = object["message"] as? [String: Any]
            guard let stopReason = message?["stop_reason"] as? String else { return .continues }
            return turnEndingStopReasons.contains(stopReason) ? .ends : .continues
        case "user":
            return userTurnEffect(of: object)
        case "system":
            return object["subtype"] as? String == "turn_duration" ? .ends : nil
        default:
            return nil
        }
    }

    private static func userTurnEffect(of object: [String: Any]) -> TurnEffect? {
        if object["isCompactSummary"] as? Bool == true { return nil }
        let content = (object["message"] as? [String: Any])?["content"]
        let leadingText: String?
        if let text = content as? String {
            leadingText = text
        } else if let blocks = content as? [[String: Any]] {
            if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return .continues }
            leadingText = blocks.first { $0["type"] as? String == "text" }?["text"] as? String
        } else {
            return nil
        }
        if let leadingText {
            if leadingText.hasPrefix(interruptionPrefix) { return .ends }
            if neutralUserPrefixes.contains(where: leadingText.hasPrefix) { return nil }
        }
        return .continues
    }
}

/// Whether the session can be typed into now. In Warp, the window title's glyph comes first: while
/// Claude works (a spinner glyph) a pending tool call is just running. With the idle glyph, a
/// pending tool call means a prompt is waiting for the user.
public enum ShiftReadiness {
    /// Warp. `windowTitle` is nil before the tab has been found; then only the transcript is checked.
    public static func refusal(windowTitle: String?, transcriptLines: [String]) -> ShiftRefusal? {
        if let windowTitle, !WarpTitle.isIdle(windowTitle: windowTitle) {
            return .working
        }
        if TranscriptState.isAwaitingUser(lines: transcriptLines) {
            return .awaitingUser
        }
        return nil
    }

    /// iTerm2 and Terminal, whose titles GearShift doesn't read: the transcript alone. A pending
    /// tool call may be running or asking the user; either way nothing is typed.
    public static func refusal(transcriptLines: [String]) -> ShiftRefusal? {
        if TranscriptState.isAwaitingUser(lines: transcriptLines) {
            return .toolPending
        }
        if TranscriptState.isBusy(lines: transcriptLines) {
            return .working
        }
        return nil
    }
}
