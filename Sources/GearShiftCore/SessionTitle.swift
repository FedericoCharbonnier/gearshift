import Foundation

/// The title Claude Code shows for a session, which it also puts in the terminal title: the last
/// `custom-title` line (from `/rename`) if there is one, else the last `ai-title` line.
public enum SessionTitle {
    public static func current(transcript: URL) -> String? {
        SessionInfoTracker(url: transcript).current().title
    }

    /// The last custom and ai title in `data`. Only lines containing the marker are parsed.
    static func lastTitles(in data: Data) -> (custom: String?, ai: String?) {
        var custom: String?
        var ai: String?
        var searchEnd = data.endIndex
        while custom == nil, let hit = data.range(of: marker, options: .backwards, in: data.startIndex..<searchEnd) {
            let lineStart = data.range(of: newline, options: .backwards, in: data.startIndex..<hit.lowerBound)?.upperBound
                ?? data.startIndex
            let lineEnd = data.range(of: newline, in: hit.upperBound..<data.endIndex)?.lowerBound ?? data.endIndex
            switch title(fromLine: String(decoding: data[lineStart..<lineEnd], as: UTF8.self)) {
            case .custom(let title): custom = title
            case .ai(let title): ai = ai ?? title
            case nil: break
            }
            searchEnd = lineStart
        }
        return (custom, ai)
    }

    private static let marker = Data(#"-title""#.utf8)
    private static let newline = Data("\n".utf8)

    private enum Title {
        case custom(String)
        case ai(String)
    }

    private static func title(fromLine line: String) -> Title? {
        guard let object = JSONLine.object(line) else { return nil }
        func trimmed(_ key: String) -> String? {
            let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        switch object["type"] as? String {
        case "custom-title": return trimmed("customTitle").map(Title.custom)
        case "ai-title": return trimmed("aiTitle").map(Title.ai)
        default: return nil
        }
    }
}

/// Follows one transcript's title. Only the title of `SessionInfoTracker`, which reads the file the
/// same way: once in full, then only what was appended.
public final class SessionTitleTracker {
    private let tracker: SessionInfoTracker

    public init(url: URL) {
        tracker = SessionInfoTracker(url: url)
    }

    public var url: URL { tracker.url }

    public func current() -> String? {
        tracker.current().title
    }
}
