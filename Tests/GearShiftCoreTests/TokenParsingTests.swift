import Foundation
@testable import GearShiftCore

/// One assistant line of a Claude Code transcript.
func claudeLine(id: String, timestamp: String, input: Int, cacheCreation: Int, cacheRead: Int, output: Int) -> String {
    #"{"type":"assistant","timestamp":"\#(timestamp)","message":{"id":"\#(id)","role":"assistant","usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheCreation),"cache_read_input_tokens":\#(cacheRead),"output_tokens":\#(output)}}}"#
}

func runTokenParsingTests() {
    suite("RollingRate") {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var rate = RollingRate()
        rate.add(TokenSample(timestamp: now.addingTimeInterval(-90), tokens: 5000))
        rate.add(TokenSample(timestamp: now.addingTimeInterval(-30), tokens: 1200))
        rate.add(TokenSample(timestamp: now.addingTimeInterval(-5), tokens: 300))
        expectEqual(rate.tokensPerMinute(now: now), 1500)
        expectEqual(rate.tokensPerMinute(now: now.addingTimeInterval(40)), 300)
    }

    suite("ClaudeTranscriptParser") {
        var parser = ClaudeTranscriptParser()
        let first = claudeLine(id: "msg_1", timestamp: "2026-09-29T18:27:46.965Z", input: 2, cacheCreation: 100, cacheRead: 5000, output: 40)
        let sample = parser.sample(fromLine: first)
        expectEqual(sample?.tokens, 142)  // cache reads are not counted
        expectEqual(sample?.timestamp, JSONLine.date("2026-09-29T18:27:46.965Z"))
        expectEqual(parser.sample(fromLine: first), nil)  // same message repeated on another line
        let grown = claudeLine(id: "msg_1", timestamp: "2026-09-29T18:27:47.100Z", input: 2, cacheCreation: 100, cacheRead: 5000, output: 90)
        expectEqual(parser.sample(fromLine: grown)?.tokens, 50)
        expectEqual(parser.sample(fromLine: #"{"type":"user","message":{"role":"user","content":"hi"},"timestamp":"2026-09-29T18:27:40Z"}"#), nil)
        expectEqual(parser.sample(fromLine: "not json"), nil)
        expect(JSONLine.date("2026-09-29T18:27:40Z") != nil, "parses timestamps without fractional seconds")
    }
}
