import Foundation
@testable import GearShiftCore

func runSessionTitleTests() {
    func aiTitle(_ title: String) -> String { #"{"type":"ai-title","aiTitle":"\#(title)","sessionId":"s1"}"# }
    func customTitle(_ title: String) -> String { #"{"type":"custom-title","customTitle":"\#(title)","sessionId":"s1"}"# }
    let user = #"{"type":"user","message":{"role":"user","content":"rename the \"ai-title\" thing"},"sessionId":"s1"}"#

    func transcript(_ lines: [String]) throws -> URL {
        let url = makeTemporaryDirectory().appendingPathComponent("s1.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    suite("SessionTitle") {
        expectEqual(SessionTitle.current(transcript: try transcript([user, aiTitle("Shiftcc app"), user])), "Shiftcc app")
        expectEqual(SessionTitle.current(transcript: try transcript([aiTitle("First"), user, aiTitle("Second")])), "Second")
        expectEqual(SessionTitle.current(transcript: try transcript([aiTitle("Auto"), customTitle("Mine"), user])), "Mine")
        // A /rename wins over any ai-title, even a later one.
        expectEqual(SessionTitle.current(transcript: try transcript([customTitle("Mine"), aiTitle("Later")])), "Mine")
        expectEqual(SessionTitle.current(transcript: try transcript([customTitle("Old"), aiTitle("A"), customTitle("New"), aiTitle("B")])), "New")
        expectEqual(SessionTitle.current(transcript: try transcript([user, #"{"type":"ai-title","aiTitle":""}"#])), nil)
        expectEqual(SessionTitle.current(transcript: try transcript([user, "not json -title\""])), nil)
        expectEqual(SessionTitle.current(transcript: try transcript([user])), nil)
        expectEqual(SessionTitle.current(transcript: makeTemporaryDirectory().appendingPathComponent("missing.jsonl")), nil)

        // A title line still being written (no newline yet) counts once it's complete JSON.
        let url = try transcript([aiTitle("Old")])
        try append(customTitle("New"), to: url)
        expectEqual(SessionTitle.current(transcript: url), "New")
    }

    suite("SessionTitle: a long transcript with the title near the start") {
        let filler = #"{"type":"assistant","message":{"content":"\#(String(repeating: "x", count: 1000))"}}"#
        let lines = [aiTitle("Early")] + Array(repeating: filler, count: 1500)  // about 1.5 MiB
        let url = try transcript(lines)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! Int
        expect(size > 1 << 20, "file is larger than 1 MiB")
        expectEqual(SessionTitle.current(transcript: url), "Early")

        // A title in the tail wins without reading the start.
        try append(customTitle("Late") + "\n", to: url)
        expectEqual(SessionTitle.current(transcript: url), "Late")
    }

    suite("SessionTitle: a /rename near the start beats ai-titles in the tail") {
        let filler = #"{"type":"assistant","message":{"content":"\#(String(repeating: "x", count: 1000))"}}"#
        let lines = [customTitle("Renamed")] + Array(repeating: filler, count: 1500) + [aiTitle("Auto")]
        expectEqual(SessionTitle.current(transcript: try transcript(lines)), "Renamed")
    }

    suite("SessionTitleTracker: reads only what was appended") {
        let url = try transcript([user, aiTitle("First")])
        let tracker = SessionTitleTracker(url: url)
        expectEqual(tracker.current(), "First")
        try append(aiTitle("Second") + "\n", to: url)
        expectEqual(tracker.current(), "Second")
        try append(customTitle("Mine") + "\n" + aiTitle("Third") + "\n", to: url)
        expectEqual(tracker.current(), "Mine")
        try append(aiTitle("Fourth") + "\n", to: url)
        expectEqual(tracker.current(), "Mine")
        // A line still being written counts once it's complete JSON, and isn't counted twice.
        try append(customTitle("Newer"), to: url)
        expectEqual(tracker.current(), "Newer")
        try append("\n" + user + "\n", to: url)
        expectEqual(tracker.current(), "Newer")
        // Replaced by a shorter file: start over.
        try (aiTitle("Fresh") + "\n").write(to: url, atomically: true, encoding: .utf8)
        expectEqual(tracker.current(), "Fresh")
        try FileManager.default.removeItem(at: url)
        expectEqual(tracker.current(), nil)
    }
}
