import Foundation

/// Why a shift didn't type anything (or stopped), as the hint shows it.
public enum ShiftRefusal: Error, Equatable, CustomStringConvertible {
    /// More than one live session has no title, so their tabs all read `Claude Code`.
    case severalUntitled
    case ambiguousTitle(String)
    case sessionGone
    case awaitingUser
    case working
    case invalidModel(String)
    case notConfirmed(String)
    /// Not confirmed in an untitled session: the command may have landed in another one.
    case notConfirmedUntitled(String)
    /// The session runs in a terminal GearShift can't drive (its `TERM_PROGRAM`, or a description).
    case unsupportedTerminal(String)
    /// An iTerm2 or Terminal session registered without a tty (the terminal's name).
    case unknownTTY(String)
    /// Two live sessions registered the same tty.
    case sharedTTY
    /// A tool call without a result, where no title glyph tells running from asking (iTerm2, Terminal).
    case toolPending

    public var description: String {
        switch self {
        case .severalUntitled: "two connected sessions have no title: /rename one (e.g. /rename backend)"
        case .ambiguousTitle(let title): "two sessions are named \(title): /rename one"
        case .sessionGone: "that session has ended: run /gearshift in a live one"
        case .awaitingUser: "Claude is waiting for you in that session: answer it first"
        case .working: "Claude is working in that session: wait until it's idle"
        case .invalidModel(let model): "\"\(model)\" isn't a valid model: fix it in settings"
        case .notConfirmed(let command): "couldn't confirm \(command) in that session"
        case .notConfirmedUntitled(let command):
            "couldn't confirm \(command) in that session: it may have gone to another \"\(ShiftTarget.untitledTabTitle)\" session. /rename this one (e.g. /rename backend)"
        case .unsupportedTerminal(let name): "GearShift supports Warp, iTerm2 and Terminal; this session runs in \(name)"
        case .unknownTTY(let terminal): "couldn't tell which \(terminal) tab that session is in: run /gearshift in it again"
        case .sharedTTY: "two connected sessions share one tab: run /gearshift in the one to shift"
        case .toolPending: "Claude is running a tool or waiting for you in that session: wait, or answer it first"
        }
    }

    /// A command the transcript didn't record after Return. In an untitled session the tab was
    /// found by the generic `Claude Code` title, so it may have gone to another session.
    public static func unconfirmed(_ command: String, targetTitle: String) -> ShiftRefusal {
        targetTitle == ShiftTarget.untitledTabTitle ? .notConfirmedUntitled(command) : .notConfirmed(command)
    }
}

/// Which tab a shift looks for. In Warp, the title: only a title Claude Code wrote into the
/// transcript will do; the folder name or nickname shown instead is for display, and could match an
/// unrelated tab. A session without one shows Claude Code's default terminal title, `Claude Code`:
/// it's searched for only while no other live session could show that title too. In iTerm2 and
/// Terminal, the tty of the session's Claude Code process.
public enum ShiftTarget {
    /// Claude Code 2.1.282's terminal title for a session without one.
    public static let untitledTabTitle = "Claude Code"

    public enum Resolved: Equatable {
        /// A Warp tab whose window title shows this.
        case warpTab(title: String)
        /// The iTerm2 or Terminal tab (or iTerm2 split pane) on this tty.
        case ttyTab(TerminalKind, tty: String)
    }

    /// The session's terminal decides: title for Warp (and records from before terminals were
    /// recorded), tty for iTerm2 and Terminal, and a refusal for anything else.
    public static func resolveTarget(sessionId: String, titles: [String: String], liveSessions: [SessionRecord]) -> Result<Resolved, ShiftRefusal> {
        guard let session = liveSessions.first(where: { $0.sessionId == sessionId }) else { return .failure(.sessionGone) }
        switch TerminalStrategy.location(of: session) {
        case .failure(let refusal):
            return .failure(refusal)
        case .success(.warpTitle):
            return resolve(sessionId: sessionId, titles: titles, liveSessions: liveSessions).map { .warpTab(title: $0) }
        case .success(.tty(let kind, let tty)):
            let sharers = liveSessions.filter { $0.tty == tty }
            guard sharers.count == 1 else { return .failure(.sharedTTY) }
            return .success(.ttyTab(kind, tty: tty))
        }
    }

    /// The Warp tab title. Sessions found by tty (in iTerm2 or Terminal) can't show up as a Warp
    /// tab, so their titles don't count; any other session's do.
    public static func resolve(sessionId: String, titles: [String: String], liveSessions: [SessionRecord]) -> Result<String, ShiftRefusal> {
        guard liveSessions.contains(where: { $0.sessionId == sessionId }) else { return .failure(.sessionGone) }
        func tabTitle(of id: String) -> String {
            guard let title = titles[id]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return untitledTabTitle
            }
            return title
        }
        let target = tabTitle(of: sessionId)
        let namesakes = liveSessions.filter {
            $0.sessionId == sessionId || (!TerminalStrategy.isFoundByTTY($0) && tabTitle(of: $0.sessionId) == target)
        }
        guard namesakes.count == 1 else {
            let isEveryNamesakeUntitled = namesakes.allSatisfy { titles[$0.sessionId].map(isBlank) ?? true }
            return .failure(isEveryNamesakeUntitled ? .severalUntitled : .ambiguousTitle(target))
        }
        return .success(target)
    }

    private static func isBlank(_ title: String) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A shift that stopped part way, with what it got done.
public struct ShiftFailure: Error, Equatable, CustomStringConvertible {
    public let reason: String
    public let commands: [ShiftCommand]
    /// Commands the transcript confirmed, from the first.
    public let confirmed: Int
    /// The next command was typed but Return wasn't pressed: it sits in the session's input.
    public let typedUnsent: Bool
    /// Return was pressed for the next command, but the transcript didn't confirm it.
    public let submittedUnconfirmed: Bool

    public init(reason: String, commands: [ShiftCommand], confirmed: Int, typedUnsent: Bool = false, submittedUnconfirmed: Bool = false) {
        self.reason = reason
        self.commands = commands
        self.confirmed = confirmed
        self.typedUnsent = typedUnsent
        self.submittedUnconfirmed = submittedUnconfirmed
    }

    /// Whether the session may now be in neither the old gear nor the new one.
    public var isGearUnknown: Bool { confirmed > 0 || submittedUnconfirmed }

    public var description: String {
        let unsent = typedUnsent && confirmed < commands.count ? "\"\(commands[confirmed].line)\" is left unsent in its input" : nil
        guard confirmed > 0, confirmed < commands.count else {
            return [reason, unsent].compactMap { $0 }.joined(separator: ": ")
        }
        let done = commands[..<confirmed].map(Self.noun).joined(separator: " and ")
        let notDone = commands[confirmed...].map(Self.noun).joined(separator: " and ")
        let summary = "\(done) set, \(notDone) not: shift again"
        return unsent.map { "\(summary) (\($0))" } ?? summary
    }

    /// `/model` → `model`.
    private static func noun(_ command: ShiftCommand) -> String {
        command.name.hasPrefix("/") ? String(command.name.dropFirst()) : command.name
    }
}

/// Which session is selected after a registry poll. A fresh `/gearshift` selects its session only
/// when nothing is selected or it's the selected one; otherwise it's announced, so that a shift
/// aimed at the selected session doesn't go elsewhere.
public enum SessionSelection {
    public struct Result: Equatable {
        public var selected: String?
        public var newestSeen: Date?
        /// A session that just connected without being selected.
        public var connected: String?

        public init(selected: String?, newestSeen: Date?, connected: String?) {
            self.selected = selected
            self.newestSeen = newestSeen
            self.connected = connected
        }
    }

    /// `sessions` are newest registration first.
    public static func update(selected: String?, newestSeen: Date?, sessions: [SessionRecord]) -> Result {
        let isSelectedLive = selected.map { id in sessions.contains { $0.sessionId == id } } ?? false
        var result = Result(selected: isSelectedLive ? selected : sessions.first?.sessionId, newestSeen: newestSeen, connected: nil)
        guard let newest = sessions.first, newestSeen.map({ newest.registeredAt > $0 }) ?? true else { return result }
        result.newestSeen = newest.registeredAt
        if isSelectedLive, newest.sessionId != selected {
            result.connected = newest.sessionId
        } else {
            result.selected = newest.sessionId
        }
        return result
    }
}

/// Splits text into the UTF-16 chunks of successive key events: `charactersPerEvent` characters
/// each, at most `maxUnitsPerEvent` units, never splitting a character, and never empty.
public enum KeyChunks {
    public static func chunks(of text: String, charactersPerEvent: Int, maxUnitsPerEvent: Int) -> [[UInt16]] {
        let perEvent = max(charactersPerEvent, 1)
        var chunks: [[UInt16]] = []
        var chunk: [UInt16] = []
        var characters = 0
        for character in text {
            let units = Array(String(character).utf16)
            if !chunk.isEmpty, characters == perEvent || chunk.count + units.count > maxUnitsPerEvent {
                chunks.append(chunk)
                chunk = []
                characters = 0
            }
            chunk += units
            characters += 1
        }
        if !chunk.isEmpty {
            chunks.append(chunk)
        }
        return chunks
    }
}
