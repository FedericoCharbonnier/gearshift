import Foundation

/// What GearShift shows about a session, read from its transcript. Shifting only ever uses `title`.
public struct SessionInfo: Equatable {
    /// The last `custom-title` (from `/rename`) if there is one, else the last `ai-title`. Claude Code
    /// also puts it in the terminal title, so it's what the Warp tab is found by.
    public var title: String?
    /// The last message the user sent, on one line. Claude Code already shortens long ones.
    public var lastPrompt: String?
    /// The model as recorded: an id from the last assistant message (`claude-opus-5-5`), or the name
    /// a later `/model` printed (`Opus 5.5 (1M context)`). Shown with `ModelName.display`.
    public var model: String?
    /// The last non-empty `gitBranch` of a transcript line (`HEAD` when detached).
    public var gitBranch: String?

    public init(title: String? = nil, lastPrompt: String? = nil, model: String? = nil, gitBranch: String? = nil) {
        self.title = title
        self.lastPrompt = lastPrompt
        self.model = model
        self.gitBranch = gitBranch
    }

    /// Whitespace runs (newlines included) become one space; longer than `maxLength` characters is
    /// cut and ends in `…`. Nil when nothing is left.
    public static func singleLine(_ text: String, maxLength: Int = 200) -> String? {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(max(maxLength - 1, 0))) + "…"
    }
}

/// The values found in one stretch of a transcript. Titles are kept apart because a custom title
/// anywhere beats every ai-title.
struct SessionInfoScan: Equatable {
    var customTitle: String?
    var aiTitle: String?
    var lastPrompt: String?
    var model: String?
    var gitBranch: String?

    var info: SessionInfo {
        SessionInfo(title: customTitle ?? aiTitle, lastPrompt: lastPrompt, model: model, gitBranch: gitBranch)
    }

    /// `self`, updated by what was found in the bytes that followed it.
    func followed(by later: SessionInfoScan) -> SessionInfoScan {
        SessionInfoScan(
            customTitle: later.customTitle ?? customTitle,
            aiTitle: later.aiTitle ?? aiTitle,
            lastPrompt: later.lastPrompt ?? lastPrompt,
            model: later.model ?? model,
            gitBranch: later.gitBranch ?? gitBranch
        )
    }

    /// Searches `data` from the end; only lines containing a field's marker are parsed.
    init(data: Data) {
        let titles = SessionTitle.lastTitles(in: data)
        customTitle = titles.custom
        aiTitle = titles.ai
        lastPrompt = Self.lastLine(in: data, containing: Self.lastPromptMarker, Self.lastPrompt)?.value
        gitBranch = Self.lastLine(in: data, containing: Self.gitBranchMarker, Self.gitBranch)?.value
        // Whichever comes later: the model an answer came from, or one `/model` switched to.
        let answered = Self.lastLine(in: data, containing: Self.modelMarker, Self.assistantModel)
        let switched = Self.lastLine(in: data, containing: Self.setModelMarker, Self.switchedModel)
        switch (answered, switched) {
        case let (answered?, switched?): model = answered.offset > switched.offset ? answered.value : switched.value
        case let (answered?, nil): model = answered.value
        case let (nil, switched?): model = switched.value
        case (nil, nil): model = nil
        }
    }

    init(customTitle: String? = nil, aiTitle: String? = nil, lastPrompt: String? = nil, model: String? = nil, gitBranch: String? = nil) {
        self.customTitle = customTitle
        self.aiTitle = aiTitle
        self.lastPrompt = lastPrompt
        self.model = model
        self.gitBranch = gitBranch
    }

    // MARK: Lines

    private static let lastPromptMarker = Data(#""last-prompt""#.utf8)
    private static let gitBranchMarker = Data(#""gitBranch":""#.utf8)
    private static let modelMarker = Data(#""model":""#.utf8)
    private static let setModelMarker = Data("Set model to".utf8)
    private static let newline = Data("\n".utf8)

    /// The last line containing `marker` that `parse` accepts, and where it starts.
    private static func lastLine<T>(
        in data: Data, containing marker: Data, _ parse: ([String: Any]) -> T?
    ) -> (value: T, offset: Int)? {
        var searchEnd = data.endIndex
        while let hit = data.range(of: marker, options: .backwards, in: data.startIndex..<searchEnd) {
            let lineStart = data.range(of: newline, options: .backwards, in: data.startIndex..<hit.lowerBound)?.upperBound
                ?? data.startIndex
            let lineEnd = data.range(of: newline, in: hit.upperBound..<data.endIndex)?.lowerBound ?? data.endIndex
            if let object = JSONLine.object(String(decoding: data[lineStart..<lineEnd], as: UTF8.self)),
               let value = parse(object) {
                return (value, lineStart)
            }
            searchEnd = lineStart
        }
        return nil
    }

    /// `{"type":"last-prompt","lastPrompt":"…"}`; some of these lines carry only a `leafUuid`.
    private static func lastPrompt(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "last-prompt", let prompt = object["lastPrompt"] as? String else { return nil }
        return SessionInfo.singleLine(prompt)
    }

    private static func gitBranch(_ object: [String: Any]) -> String? {
        let branch = (object["gitBranch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch?.isEmpty == false ? branch : nil
    }

    /// The main thread's assistant messages; `<synthetic>` ones were made up by Claude Code itself.
    private static func assistantModel(_ object: [String: Any]) -> String? {
        guard object["type"] as? String == "assistant", object["isSidechain"] as? Bool != true,
              let message = object["message"] as? [String: Any],
              let model = (message["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !model.isEmpty, model != "<synthetic>"
        else { return nil }
        return model
    }

    /// `/model`'s output: a `system`/`local_command` line whose `content` is
    /// `<local-command-stdout>Set model to …</local-command-stdout>` (older versions: the same
    /// string as a user message's content).
    private static func switchedModel(_ object: [String: Any]) -> String? {
        guard object["isSidechain"] as? Bool != true else { return nil }
        let content: String?
        switch object["type"] as? String {
        case "system":
            content = object["subtype"] as? String == "local_command" ? object["content"] as? String : nil
        case "user":
            content = (object["message"] as? [String: Any])?["content"] as? String
        default:
            content = nil
        }
        return content.flatMap(ModelName.switched(commandOutput:))
    }
}

/// Follows one transcript. A custom title can be anywhere in the file, so the whole file is read
/// once; after that only what was appended. A line still being written counts once it is complete
/// JSON.
public final class SessionInfoTracker {
    public let url: URL
    private var offset: UInt64 = 0
    private var found = SessionInfoScan()
    private var pending = Data()

    public init(url: URL) {
        self.url = url
    }

    public func current() -> SessionInfo {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            reset()
            return SessionInfo()
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            reset()  // truncated or replaced
        }
        if size > offset, (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() {
            offset += UInt64(data.count)
            pending += data
            if let lastNewline = pending.lastIndex(of: UInt8(ascii: "\n")) {
                found = found.followed(by: SessionInfoScan(data: Data(pending[..<lastNewline])))
                pending = Data(pending[pending.index(after: lastNewline)...])
            }
        }
        let partial = pending.isEmpty ? SessionInfoScan() : SessionInfoScan(data: pending)
        return found.followed(by: partial).info
    }

    private func reset() {
        offset = 0
        found = SessionInfoScan()
        pending = Data()
    }
}
