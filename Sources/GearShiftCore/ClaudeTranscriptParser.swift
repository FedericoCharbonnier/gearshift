import Foundation

/// Turns Claude Code transcript lines into token samples. One API response is written on several
/// lines (one per content block) repeating the same `message.id` and usage, so each id is counted
/// once; if a later line reports more tokens, only the difference is counted. Cache reads are left
/// out, otherwise they would pin the needle.
public struct ClaudeTranscriptParser {
    private static let countedFields = ["input_tokens", "cache_creation_input_tokens", "output_tokens"]
    private var countedTokens: [String: Int] = [:]

    public init() {}

    public mutating func sample(fromLine line: String) -> TokenSample? {
        // Most lines carry no usage; skip them before paying for JSON parsing.
        guard line.contains(#""usage""#),
              let object = JSONLine.object(line),
              let message = object["message"] as? [String: Any],
              let id = message["id"] as? String,
              let usage = message["usage"] as? [String: Any],
              let timestamp = (object["timestamp"] as? String).flatMap(JSONLine.date)
        else { return nil }
        let tokens = Self.countedFields.reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
        let previous = countedTokens[id] ?? 0
        guard tokens > previous else { return nil }
        countedTokens[id] = tokens
        return TokenSample(timestamp: timestamp, tokens: tokens - previous)
    }
}
