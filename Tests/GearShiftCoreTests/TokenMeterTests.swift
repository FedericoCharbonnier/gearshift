import Foundation
@testable import GearShiftCore

func runTokenMeterTests() {
    suite("TranscriptTail") {
        let url = makeTemporaryDirectory().appendingPathComponent("t.jsonl")
        let tail = TranscriptTail(url: url)
        expectEqual(tail.readNewLines(), [])  // file doesn't exist yet
        try "a\nb".write(to: url, atomically: false, encoding: .utf8)
        expectEqual(tail.readNewLines(), ["a"])  // "b" is incomplete
        try append("c\nd\n", to: url)
        expectEqual(tail.readNewLines(), ["bc", "d"])
        expectEqual(tail.readNewLines(), [])
        try "e\n".write(to: url, atomically: false, encoding: .utf8)  // truncated and rewritten
        expectEqual(tail.readNewLines(), ["e"])

        // "é" is 0xC3 0xA9; its bytes arrive in two appends.
        try Data([UInt8(ascii: "a"), 0xC3]).write(to: url)
        let accented = TranscriptTail(url: url)
        expectEqual(accented.readNewLines(), [])
        try append(Data([0xA9, UInt8(ascii: "\n")]), to: url)
        expectEqual(accented.readNewLines(), ["aé"])
    }

    suite("TranscriptTail: starting at the end reads only what's appended later") {
        let url = makeTemporaryDirectory().appendingPathComponent("t.jsonl")
        try "old 1\nold 2\npartial".write(to: url, atomically: false, encoding: .utf8)
        let tail = TranscriptTail(url: url, startingAtEnd: true)
        expectEqual(tail.readNewLines(), [])
        try append(" rest\nnew 1\n", to: url)
        // The line that was partial at the start is skipped: its start was before the tail began.
        expectEqual(tail.readNewLines(), ["new 1"])
        let missing = TranscriptTail(url: url.deletingLastPathComponent().appendingPathComponent("none.jsonl"), startingAtEnd: true)
        expectEqual(missing.readNewLines(), [])

        let boundary = makeTemporaryDirectory().appendingPathComponent("b.jsonl")
        try "old\n".write(to: boundary, atomically: false, encoding: .utf8)
        let atBoundary = TranscriptTail(url: boundary, startingAtEnd: true)
        try append("new\n", to: boundary)
        expectEqual(atBoundary.readNewLines(), ["new"])
    }

    suite("TranscriptTail: last lines") {
        let url = makeTemporaryDirectory().appendingPathComponent("t.jsonl")
        expectEqual(TranscriptTail.lastLines(of: url, maxBytes: 100), [])
        try "one\ntwo\nthree\nfour".write(to: url, atomically: false, encoding: .utf8)
        expectEqual(TranscriptTail.lastLines(of: url, maxBytes: 100), ["one", "two", "three", "four"])
        // The cut line at the start is dropped.
        expectEqual(TranscriptTail.lastLines(of: url, maxBytes: 12), ["three", "four"])
        expectEqual(TranscriptTail.lastLines(of: url, maxBytes: 11), ["three", "four"])
    }

    suite("TranscriptTail: a long file is read from its last few MiB") {
        let filler = String(repeating: "x", count: 92)
        func fillerLine(_ index: Int) -> String { "f\(String(format: "%06d", index))" + filler }  // 99 bytes + newline
        let limit = Int(TranscriptTail.initialReadLimit)
        let count = 50_000

        // "last" makes the cut fall mid-line; "end" puts it right after a newline, keeping that line.
        for (lastLine, cutsMidLine) in [("last", true), ("end", false)] {
            let url = makeTemporaryDirectory().appendingPathComponent("long.jsonl")
            let text = (0..<count).map(fillerLine).joined(separator: "\n") + "\n" + lastLine + "\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
            let skipped = text.utf8.count - limit
            expectEqual(skipped % 100 != 0, cutsMidLine)

            let lines = TranscriptTail(url: url).readNewLines()
            expectEqual(lines.last, lastLine)
            let fillers = lines.dropLast()
            expect(fillers.allSatisfy { $0.count == 99 && $0.hasPrefix("f") }, "no truncated fragment")
            expectEqual(fillers.first, fillerLine((skipped + 99) / 100))
            expectEqual(fillers.count, count - (skipped + 99) / 100)
        }
    }

    suite("TokenMeter") {
        let transcript = makeTemporaryDirectory().appendingPathComponent("session.jsonl")
        let now = JSONLine.date("2026-09-29T18:28:00.000Z")!
        let lines = [
            claudeLine(id: "old", timestamp: "2026-09-29T18:26:00.000Z", input: 0, cacheCreation: 0, cacheRead: 0, output: 9999),
            claudeLine(id: "m1", timestamp: "2026-09-29T18:27:30.000Z", input: 10, cacheCreation: 1000, cacheRead: 40000, output: 200),
            claudeLine(id: "m1", timestamp: "2026-09-29T18:27:30.100Z", input: 10, cacheCreation: 1000, cacheRead: 40000, output: 200),
            claudeLine(id: "m2", timestamp: "2026-09-29T18:27:50.000Z", input: 5, cacheCreation: 0, cacheRead: 41000, output: 300),
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: transcript, atomically: true, encoding: .utf8)

        let meter = TokenMeter()
        expectEqual(meter.poll(source: .claude(transcript), now: now), 1515)
        try append(claudeLine(id: "m3", timestamp: "2026-09-29T18:28:10.000Z", input: 0, cacheCreation: 0, cacheRead: 0, output: 485) + "\n", to: transcript)
        expectEqual(meter.poll(source: .claude(transcript), now: now.addingTimeInterval(15)), 2000)
        expectEqual(meter.poll(source: nil, now: now), 0)
    }

    suite("TokenMeter: keeps each source's progress") {
        let directory = makeTemporaryDirectory()
        let first = directory.appendingPathComponent("a.jsonl")
        let now = JSONLine.date("2026-09-29T18:28:00.000Z")!
        try (claudeLine(id: "a1", timestamp: "2026-09-29T18:27:30.000Z", input: 100, cacheCreation: 0, cacheRead: 0, output: 0) + "\n")
            .write(to: first, atomically: true, encoding: .utf8)
        /// Overwrites what was already read, in place: a meter that resumes won't notice, one that
        /// re-reads the file from the start loses those samples.
        func blankReadPart() throws {
            let size = try FileManager.default.attributesOfItem(atPath: first.path)[.size] as! Int
            let handle = try FileHandle(forWritingTo: first)
            try handle.write(contentsOf: Data(repeating: UInt8(ascii: " "), count: size - 1))
            try handle.close()
        }
        func other(_ index: Int) -> TokenMeter.Source { .claude(directory.appendingPathComponent("other-\(index).jsonl")) }

        let meter = TokenMeter()
        expectEqual(meter.poll(source: .claude(first), now: now), 100)
        expectEqual(meter.poll(source: other(0), now: now), 0)
        try blankReadPart()
        try append(claudeLine(id: "a2", timestamp: "2026-09-29T18:27:40.000Z", input: 20, cacheCreation: 0, cacheRead: 0, output: 0) + "\n", to: first)
        expectEqual(meter.poll(source: .claude(first), now: now), 120)  // resumed, not re-read or double-counted

        // Up to maxSources are kept; the least recently used one beyond that is dropped.
        for index in 1..<TokenMeter.maxSources {
            _ = meter.poll(source: other(index), now: now)
        }
        expectEqual(meter.poll(source: .claude(first), now: now), 120)
        for index in 1...TokenMeter.maxSources {
            _ = meter.poll(source: other(index), now: now)
        }
        expectEqual(meter.poll(source: .claude(first), now: now), 20)  // dropped, so read again from the start
    }
}
