import Foundation

/// The AppleScript GearShift sends to iTerm2 and Terminal, and how it reads the answers.
///
/// iTerm2 is typed into in the background (`writeSource`): each script finds the one session on the
/// tty and writes to it with `write text … newline false`, without activating, raising or selecting
/// anything; the text and the carriage return that submits it are two separate writes, so that the
/// session's readiness is checked again before Return, and Return is a lone CR, which Claude Code's
/// raw-mode input takes as Enter whatever line ending `write text` would add by itself.
///
/// Terminal's only way in, `do script`, always appends its own line ending in the same write, so
/// text and Return can't be sent apart: Terminal is focused (`focusSource`, `frontSource`) and typed
/// into with key events, like Warp.
///
/// Each script starts by checking that the app is running, so that it never launches it. The tty is
/// put into the source only once `TTYPath` has validated it: `/dev/ttys` and digits.
public enum TerminalScripts {
    /// The iTerm2 dictionary (3.7) calls the app `iTerm`, and Terminal's is Terminal; both are
    /// addressed by bundle identifier, which doesn't change.
    private static func header(_ kind: TerminalKind) -> (bundleId: String, guardLine: String)? {
        guard kind.isFoundByTTY, let bundleId = kind.bundleIdentifier else { return nil }
        return (bundleId, #"if application id "\#(bundleId)" is not running then return "not running""#)
    }

    /// Selects the tab (and, in iTerm2, the split pane) whose tty is `tty`, brings its window to the
    /// front and activates the app, only if exactly one matches. Answers `focused`,
    /// `matches <n>` (none or several: nothing is selected) or `not running`.
    public static func focusSource(kind: TerminalKind, tty: String) -> String? {
        guard TTYPath.isValid(tty), let (bundleId, guardLine) = header(kind) else { return nil }
        switch kind {
        case .terminal:
            return """
            \(guardLine)
            tell application id "\(bundleId)"
            \twith timeout of 3 seconds
            \t\tset matchCount to 0
            \t\tset matchWindow to missing value
            \t\tset matchTab to missing value
            \t\trepeat with aWindow in (every window)
            \t\t\trepeat with aTab in (every tab of aWindow)
            \t\t\t\tif (tty of aTab) is "\(tty)" then
            \t\t\t\t\tset matchCount to matchCount + 1
            \t\t\t\t\tset matchWindow to contents of aWindow
            \t\t\t\t\tset matchTab to contents of aTab
            \t\t\t\tend if
            \t\t\tend repeat
            \t\tend repeat
            \t\tif matchCount is not 1 then return "matches " & matchCount
            \t\tif miniaturized of matchWindow then set miniaturized of matchWindow to false
            \t\tset selected of matchTab to true
            \t\tset index of matchWindow to 1
            \t\tactivate
            \t\treturn "focused"
            \tend timeout
            end tell
            """
        case .iterm:
            return """
            \(guardLine)
            tell application id "\(bundleId)"
            \twith timeout of 3 seconds
            \(itermMatch(tty: tty))
            \t\tselect matchTab
            \t\tselect session matchSessionIndex of matchTab
            \t\tselect matchWindow
            \t\tactivate
            \t\treturn "focused"
            \tend timeout
            end tell
            """
        case .warp, .other:
            return nil
        }
    }

    /// iTerm2's lookup of the one session on `tty`, as lines of a `tell` block: counts the sessions
    /// (split panes) on the tty in every tab of every window, returns `matches <n>` unless exactly
    /// one is, and leaves `matchWindow`, `matchTab` and `matchSession` set to it. iTerm2 can't
    /// resolve `contents of` a `repeat with … in every window` item (-1728), so the match is kept as
    /// the window id plus tab and session indexes and looked up again.
    private static func itermMatch(tty: String) -> String {
        """
        \t\tset matchCount to 0
        \t\tset matchWindowId to missing value
        \t\tset matchTabIndex to 0
        \t\tset matchSessionIndex to 0
        \t\trepeat with w from 1 to (count of windows)
        \t\t\tset aWindow to window w
        \t\t\trepeat with t from 1 to (count of tabs of aWindow)
        \t\t\t\tset aTab to tab t of aWindow
        \t\t\t\trepeat with s from 1 to (count of sessions of aTab)
        \t\t\t\t\tif (tty of session s of aTab) is "\(tty)" then
        \t\t\t\t\t\tset matchCount to matchCount + 1
        \t\t\t\t\t\tset matchWindowId to id of aWindow
        \t\t\t\t\t\tset matchTabIndex to t
        \t\t\t\t\t\tset matchSessionIndex to s
        \t\t\t\t\tend if
        \t\t\t\tend repeat
        \t\t\tend repeat
        \t\tend repeat
        \t\tif matchCount is not 1 then return "matches " & matchCount
        \t\tset matchWindow to window id matchWindowId
        \t\tset matchTab to tab matchTabIndex of matchWindow
        \t\tset matchSession to session matchSessionIndex of matchTab
        """
    }

    /// What one background write sends to the session.
    public enum ScriptedInput: Equatable {
        /// A command line's text, without any line ending.
        case text(String)
        /// A lone carriage return (`\r`): Enter, for Claude Code's raw-mode input.
        case carriageReturn
    }

    /// iTerm2 only: writes `input` to the one session on `tty`, in the background. Nothing is
    /// activated, raised or selected, and nothing is written unless exactly one session is on the tty,
    /// counted and read again by this same script right before the write. Answers `sent`,
    /// `matches <n>` or `not running`.
    ///
    /// Nil for Terminal (its `do script` appends its own line ending), for another terminal, for a
    /// tty that isn't one, and for text that is empty or holds a control character (a CR or LF in
    /// the text would submit it early).
    public static func writeSource(kind: TerminalKind, tty: String, input: ScriptedInput) -> String? {
        guard kind == .iterm, TTYPath.isValid(tty), let (bundleId, guardLine) = header(kind) else { return nil }
        let textExpression: String
        switch input {
        case .text(let text):
            guard !text.isEmpty, !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
                return nil
            }
            textExpression = appleScriptLiteral(text)
        case .carriageReturn:
            textExpression = "(character id 13)"
        }
        return """
        \(guardLine)
        tell application id "\(bundleId)"
        \twith timeout of 3 seconds
        \(itermMatch(tty: tty))
        \t\tif (tty of matchSession) is not "\(tty)" then return "matches 0"
        \t\ttell matchSession to write text \(textExpression) newline false
        \t\treturn "sent"
        \tend timeout
        end tell
        """
    }

    /// `text` as an AppleScript string literal: in double quotes, with `\` and `"` escaped.
    public static func appleScriptLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Reads, without changing anything, where typed keys would go: whether the app is frontmost,
    /// and the tty and title of its front window's selected tab (Terminal) or current session
    /// (iTerm2). Answers `front`, the tty and the window title on three lines, or `not frontmost` /
    /// `not running`.
    public static func frontSource(kind: TerminalKind) -> String? {
        guard let (bundleId, guardLine) = header(kind) else { return nil }
        let ttyOfFront = kind == .terminal
            ? "tty of selected tab of frontWindow"
            : "tty of current session of frontWindow"
        let frontWindow = kind == .terminal ? "front window" : "current window"
        return """
        \(guardLine)
        tell application id "\(bundleId)"
        \twith timeout of 2 seconds
        \t\tif not frontmost then return "not frontmost"
        \t\tset frontWindow to \(frontWindow)
        \t\treturn "front" & linefeed & (\(ttyOfFront)) & linefeed & (name of frontWindow)
        \tend timeout
        end tell
        """
    }

    public enum FocusOutcome: Equatable {
        case focused
        case notRunning
        /// Not exactly one tab (or pane) had the tty: this many did.
        case matches(Int)
        case unexpected(String)
    }

    public static func focusOutcome(_ answer: String) -> FocusOutcome {
        switch answer {
        case "focused": return .focused
        case "not running": return .notRunning
        default:
            let prefix = "matches "
            if answer.hasPrefix(prefix), let count = Int(answer.dropFirst(prefix.count)), count != 1 {
                return .matches(count)
            }
            return .unexpected(answer)
        }
    }

    public enum WriteOutcome: Equatable {
        case sent
        case notRunning
        /// Not exactly one session had the tty: this many did. Nothing was written.
        case matches(Int)
        case unexpected(String)
    }

    public static func writeOutcome(_ answer: String) -> WriteOutcome {
        switch answer {
        case "sent": return .sent
        case "not running": return .notRunning
        default:
            let prefix = "matches "
            if answer.hasPrefix(prefix), let count = Int(answer.dropFirst(prefix.count)), count != 1 {
                return .matches(count)
            }
            return .unexpected(answer)
        }
    }

    public enum FrontState: Equatable {
        case notRunning
        case notFrontmost
        case front(tty: String, windowTitle: String)
        case unexpected
    }

    public static func frontState(_ answer: String) -> FrontState {
        switch answer {
        case "not running": return .notRunning
        case "not frontmost": return .notFrontmost
        default:
            let parts = answer.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "front" else { return .unexpected }
            return .front(tty: String(parts[1]), windowTitle: String(parts[2]))
        }
    }

    /// Whether keys typed now would reach the session: the app is frontmost, its front window's
    /// selected tab (or pane) is on the session's tty, and that window is the one that has keyboard
    /// focus (its title is the focused window's, read through Accessibility).
    public static func isOnSession(_ state: FrontState, tty: String, focusedWindowTitle: String?) -> Bool {
        guard case .front(let frontTTY, let windowTitle) = state, frontTTY == tty, let focusedWindowTitle else { return false }
        return windowTitle == focusedWindowTitle
    }

    /// AppleScript errors that call for their own hint.
    public enum ScriptError: Equatable {
        /// `errAEEventNotPermitted`: the user didn't allow GearShift to control the app (Automation).
        case notPermitted
        /// `procNotFound`: the app quit.
        case notRunning
        /// `errAETimeout`.
        case timedOut
        case other(Int)

        public init(code: Int) {
            switch code {
            case -1743: self = .notPermitted
            case -600: self = .notRunning
            case -1712: self = .timedOut
            default: self = .other(code)
            }
        }
    }
}
