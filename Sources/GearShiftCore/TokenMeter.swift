import Foundation

/// Tokens/min for the selected session's transcript. Poll about once a second.
/// Each source keeps its read position and samples, so switching back to a session resumes where it
/// left off instead of reading the transcript again.
public final class TokenMeter {
    public enum Source: Hashable {
        case claude(URL)
    }

    /// Sources remembered at once; the least recently polled one beyond this is dropped.
    static let maxSources = 8

    private final class Reader {
        let tail: TranscriptTail
        var parser = ClaudeTranscriptParser()
        var rate = RollingRate()

        init(_ source: Source) {
            switch source {
            case .claude(let url):
                tail = TranscriptTail(url: url)
            }
        }
    }

    private var readers: [Source: Reader] = [:]
    /// Least recently polled first.
    private var pollOrder: [Source] = []

    public init() {}

    public func poll(source: Source?, now: Date = Date()) -> Int {
        guard let source else { return 0 }
        let reader = reader(for: source)
        for line in reader.tail.readNewLines() {
            if let sample = reader.parser.sample(fromLine: line) {
                reader.rate.add(sample)
            }
        }
        return reader.rate.tokensPerMinute(now: now)
    }

    private func reader(for source: Source) -> Reader {
        pollOrder.removeAll { $0 == source }
        pollOrder.append(source)
        if pollOrder.count > Self.maxSources {
            readers[pollOrder.removeFirst()] = nil
        }
        if let reader = readers[source] {
            return reader
        }
        let reader = Reader(source)
        readers[source] = reader
        return reader
    }
}
