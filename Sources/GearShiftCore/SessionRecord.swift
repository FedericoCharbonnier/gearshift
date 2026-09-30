import Foundation

/// A Claude Code session connected with `/gearshift`. `register.sh` writes it as JSON, so the keys
/// and the date format are shared with that script.
public struct SessionRecord: Codable, Equatable {
    public var sessionId: String
    /// The session's working directory.
    public var cwd: String
    public var transcriptPath: String
    /// The `claude` process; the session is gone when it exits.
    public var claudePid: Int32
    public var registeredAt: Date
    /// The user's own name for the session, from `/gearshift <nickname>`. Display only: the tab is
    /// always found by the session's Claude title (Warp) or its tty (iTerm2, Terminal).
    public var nickname: String?
    /// The terminal it runs in, from `TERM_PROGRAM`; nil in records from before it was recorded,
    /// which are Warp's.
    public var terminal: TerminalKind?
    /// The Claude Code process's controlling tty, e.g. `/dev/ttys007`; nil when it had none, or in
    /// older records. Only a valid pseudo-terminal path is kept.
    public var tty: String?
    /// `TERM_PROGRAM` of an unsupported terminal (`terminal` is `other`), for the hint.
    public var termProgram: String?

    public init(
        sessionId: String, cwd: String, transcriptPath: String, claudePid: Int32, registeredAt: Date, nickname: String? = nil,
        terminal: TerminalKind? = nil, tty: String? = nil, termProgram: String? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.claudePid = claudePid
        self.registeredAt = registeredAt
        self.nickname = nickname.flatMap(Self.cleanNickname)
        self.terminal = terminal
        self.tty = tty.flatMap { TTYPath.isValid($0) ? $0 : nil }
        self.termProgram = termProgram.flatMap(Self.cleanTermProgram)
    }

    enum CodingKeys: String, CodingKey {
        case sessionId, cwd, transcriptPath, claudePid, registeredAt, nickname, terminal, tty, termProgram
    }

    /// Trimmed; nil when blank.
    private static func cleanNickname(_ nickname: String) -> String? {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 1–32 of `[A-Za-z0-9._-]`, as `register.sh` writes it; anything else is dropped.
    private static func cleanTermProgram(_ name: String) -> String? {
        let isPlain = (1...32).contains(name.count) && name.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0))
        }
        return isPlain ? name : nil
    }

    private static let wholeSecondFormatter = ISO8601DateFormatter()
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Whole seconds as before; milliseconds when there are any (`register.sh` writes them), since
    /// the newest registration decides what gets selected.
    static func encodeDate(_ date: Date) -> String {
        let isWholeSecond = date.timeIntervalSince1970.rounded(.down) == date.timeIntervalSince1970
        return (isWholeSecond ? wholeSecondFormatter : fractionalFormatter).string(from: date)
    }

    // The date is an ISO 8601 string whatever the coder's date strategy, so a plain
    // `JSONDecoder()` reads what the script writes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let registeredAt = try container.decode(String.self, forKey: .registeredAt)
        guard let date = JSONLine.date(registeredAt) else {
            throw DecodingError.dataCorruptedError(
                forKey: .registeredAt, in: container, debugDescription: "not an ISO 8601 date: \(registeredAt)")
        }
        self.init(
            sessionId: try container.decode(String.self, forKey: .sessionId),
            cwd: try container.decode(String.self, forKey: .cwd),
            transcriptPath: try container.decode(String.self, forKey: .transcriptPath),
            claudePid: try container.decode(Int32.self, forKey: .claudePid),
            registeredAt: date,
            nickname: try container.decodeIfPresent(String.self, forKey: .nickname),
            terminal: try container.decodeIfPresent(String.self, forKey: .terminal).map(TerminalKind.init(recorded:)),
            tty: try container.decodeIfPresent(String.self, forKey: .tty),
            termProgram: try container.decodeIfPresent(String.self, forKey: .termProgram)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(transcriptPath, forKey: .transcriptPath)
        try container.encode(claudePid, forKey: .claudePid)
        try container.encode(Self.encodeDate(registeredAt), forKey: .registeredAt)
        try container.encodeIfPresent(nickname, forKey: .nickname)
        try container.encodeIfPresent(terminal, forKey: .terminal)
        try container.encodeIfPresent(tty, forKey: .tty)
        try container.encodeIfPresent(termProgram, forKey: .termProgram)
    }
}
