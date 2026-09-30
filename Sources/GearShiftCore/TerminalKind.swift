import Foundation

/// The terminal a session runs in, as `register.sh` recorded it from `TERM_PROGRAM`. It decides how
/// the session's tab is found: by window title in Warp, by tty in iTerm2 and Terminal.
public enum TerminalKind: String, Codable, CaseIterable, Equatable {
    case warp
    case iterm
    case terminal
    case other

    /// `register.sh`'s mapping, mirrored for tests and documentation.
    public static func from(termProgram: String?) -> TerminalKind {
        switch termProgram {
        case "WarpTerminal": .warp
        case "iTerm.app": .iterm
        case "Apple_Terminal": .terminal
        default: .other
        }
    }

    /// A record's `terminal` value; a value a newer script might write is another terminal.
    public init(recorded value: String) {
        self = TerminalKind(rawValue: value) ?? .other
    }

    /// Short, for the session picker and hints.
    public var displayName: String {
        switch self {
        case .warp: "Warp"
        case .iterm: "iTerm"
        case .terminal: "Terminal"
        case .other: "other"
        }
    }

    /// The app's bundle identifier, for the terminals GearShift drives.
    public var bundleIdentifier: String? {
        switch self {
        case .warp: "dev.warp.Warp-Stable"
        case .iterm: "com.googlecode.iterm2"
        case .terminal: "com.apple.Terminal"
        case .other: nil
        }
    }

    /// Whether the session's tab is found by its tty (rather than its window title).
    public var isFoundByTTY: Bool {
        self == .iterm || self == .terminal
    }
}

/// A macOS pseudo-terminal device path, e.g. `/dev/ttys007`: what `register.sh` records and what
/// iTerm2 and Terminal report for a tab. Nothing else is accepted, since it's also put into an
/// AppleScript source.
public enum TTYPath {
    public static func isValid(_ path: String) -> Bool {
        let prefix = "/dev/ttys"
        guard path.hasPrefix(prefix) else { return false }
        let digits = path.dropFirst(prefix.count)
        return (1...5).contains(digits.count) && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

/// Where a session's tab is looked for.
public enum SessionLocation: Equatable {
    /// A Warp tab, by the session's title in the window title (the only way before v2.1).
    case warpTitle
    /// An iTerm2 or Terminal tab, by the tty of the Claude Code process.
    case tty(TerminalKind, String)
}

public enum TerminalStrategy {
    /// Records from before terminals were recorded are Warp's, as GearShift supported only Warp.
    public static func location(of record: SessionRecord) -> Result<SessionLocation, ShiftRefusal> {
        let kind = record.terminal ?? .warp
        switch kind {
        case .warp:
            return .success(.warpTitle)
        case .iterm, .terminal:
            guard let tty = record.tty else { return .failure(.unknownTTY(kind.displayName)) }
            return .success(.tty(kind, tty))
        case .other:
            return .failure(.unsupportedTerminal(record.termProgram ?? "another terminal"))
        }
    }

    /// Whether a live session's tab is found by tty, so its title can't be confused with a Warp tab's.
    public static func isFoundByTTY(_ record: SessionRecord) -> Bool {
        if case .success(.tty) = location(of: record) { return true }
        return false
    }
}
