import AppKit
import ApplicationServices
import GearShiftCore

/// Types into one session's tab. Warp and Terminal are brought to the front on that tab and get key
/// events; iTerm2 takes the text in the background through AppleScript, and nothing comes forward.
/// A driver is made for one shift and used from one background queue; everything blocks.
protocol TerminalDriver: AnyObject {
    /// For hints: "Warp", "iTerm", "Terminal".
    var terminalName: String { get }
    /// The error for a shift that ran out of time before a keystroke.
    var timeoutError: Error { get }
    /// Whether text and Return reach the session as key events posted to the frontmost terminal, so
    /// that it must be focused first and no key or mouse button may be held while typing.
    var postsKeyEvents: Bool { get }
    /// Gets the session ready to type into, or throws without having typed: a focusing driver
    /// remembers what was in front, then activates the terminal with the session's tab selected.
    func focusSession(deadline: Date) throws
    /// Right before each keystroke: throws unless the keystroke would reach the session (a focusing
    /// driver: the terminal is frontmost on the session's tab). Returns the window title when the
    /// session's readiness is judged by it (Warp's glyph), nil when only the transcript counts.
    func verifyFocus() throws -> String?
    func typeText(_ text: String) throws
    func pressReturn() throws
    /// Once nothing more will be typed, after success or failure: brings back the app, window and tab
    /// that were in front before `focusSession`, as far as the driver can. Only while the terminal
    /// is still frontmost: otherwise the user has already gone elsewhere. Never types.
    func restorePreviousFocus()
}

/// What was in front before a focusing driver brought its terminal forward.
struct PreviousFront {
    let app: NSRunningApplication

    /// Nil when no app is frontmost.
    static func capture() -> PreviousFront? {
        NSWorkspace.shared.frontmostApplication.map(PreviousFront.init)
    }

    func isApp(pid: pid_t) -> Bool {
        app.processIdentifier == pid
    }

    /// Brings the app back the way terminals are brought forward: activation, then Accessibility's
    /// frontmost, which also works where macOS 14's cooperative activation would refuse. GearShift
    /// itself included.
    func reactivateApp() {
        guard !app.isTerminated else { return }
        app.activate()
        AXUIElementSetAttributeValue(AX.application(pid: app.processIdentifier), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    }
}

enum ScriptedTerminalError: Error, CustomStringConvertible {
    case notRunning(String)
    case couldNotActivate(String)
    case sessionNotFound(String)
    case duplicateSessions(String)
    case focusLost(String)
    case automationDenied(String)
    case scriptFailed(String, Int)
    case unexpectedAnswer(String)
    case timedOut(String)
    case unsafeText(String)

    var description: String {
        switch self {
        case .notRunning(let app): "\(app) isn't running"
        case .couldNotActivate(let app): "couldn't bring \(app) to the front on that session: shift again"
        case .sessionNotFound(let app): "that session's tab wasn't found in \(app): is it still open?"
        case .duplicateSessions(let app): "two \(app) tabs have that session's tty: close one"
        case .focusLost(let app): "\(app) lost focus: shift again"
        case .automationDenied(let app):
            "allow GearShift to control \(app) in System Settings › Privacy & Security › Automation"
        case .scriptFailed(let app, let code): "couldn't talk to \(app) (AppleScript error \(code)): shift again"
        case .unexpectedAnswer(let app): "\(app) gave an unexpected answer: shift again"
        case .timedOut(let app): "\(app) took too long: shift again"
        case .unsafeText(let app): "refused to write that command to \(app)"
        }
    }
}

/// Runs AppleScript for a driver, here, on the caller's (background) queue. GearShift runs one shift
/// at a time, so scripts never run concurrently.
struct TerminalAppleScript {
    let terminalName: String

    func run(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else { throw ScriptedTerminalError.scriptFailed(terminalName, 0) }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            switch TerminalScripts.ScriptError(code: code) {
            case .notPermitted: throw ScriptedTerminalError.automationDenied(terminalName)
            case .notRunning: throw ScriptedTerminalError.notRunning(terminalName)
            case .timedOut: throw ScriptedTerminalError.timedOut(terminalName)
            case .other(let code): throw ScriptedTerminalError.scriptFailed(terminalName, code)
            }
        }
        return result.stringValue ?? ""
    }
}

/// Drives iTerm2 in the background: every write is one AppleScript that finds the one session on
/// the tty and writes to it with `write text … newline false` (`TerminalScripts.writeSource`), with
/// no activation, raising, selection or focus change. The command's text and the carriage return
/// that submits it are separate writes, so the transcript is checked again in between.
final class ITermDriver: TerminalDriver {
    let tty: String
    let terminalName = TerminalKind.iterm.displayName
    let postsKeyEvents = false
    private let script = TerminalAppleScript(terminalName: TerminalKind.iterm.displayName)

    var timeoutError: Error { ScriptedTerminalError.timedOut(terminalName) }

    init(tty: String) {
        self.tty = tty
    }

    /// Nothing to focus: each write finds the session again. Only checks that iTerm2 runs, so a
    /// shift into a quit iTerm2 says so before anything else.
    func focusSession(deadline: Date) throws {
        guard let bundleIdentifier = TerminalKind.iterm.bundleIdentifier,
              NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains(where: { !$0.isTerminated })
        else { throw ScriptedTerminalError.notRunning(terminalName) }
        guard Date() < deadline else { throw timeoutError }
    }

    /// The write script itself refuses unless exactly one session is on the tty.
    func verifyFocus() throws -> String? {
        nil
    }

    func typeText(_ text: String) throws {
        try write(.text(text))
    }

    func pressReturn() throws {
        try write(.carriageReturn)
    }

    /// Nothing was brought forward.
    func restorePreviousFocus() {}

    private func write(_ input: TerminalScripts.ScriptedInput) throws {
        guard let source = TerminalScripts.writeSource(kind: .iterm, tty: tty, input: input) else {
            throw ScriptedTerminalError.unsafeText(terminalName)
        }
        switch TerminalScripts.writeOutcome(try script.run(source)) {
        case .sent:
            break
        case .notRunning:
            throw ScriptedTerminalError.notRunning(terminalName)
        case .matches(0):
            throw ScriptedTerminalError.sessionNotFound(terminalName)
        case .matches:
            throw ScriptedTerminalError.duplicateSessions(terminalName)
        case .unexpected:
            throw ScriptedTerminalError.unexpectedAnswer(terminalName)
        }
    }
}

/// Drives Terminal (or, as a fallback, iTerm2) in the foreground: the session's tab is found and
/// selected by its tty through AppleScript, and keys are posted to the app's process like in Warp.
/// Terminal can't be typed into in the background: `do script` always appends its own line ending
/// in the same write. Before every keystroke, AppleScript must say the app is frontmost with its
/// front window on that tty, and that window must be the one with keyboard focus (Accessibility).
/// Afterwards, the app that was in front comes back; if that was this terminal, so does the tab
/// that was in front.
class ScriptedTerminalDriver: TerminalDriver {
    private static let activationTimeout: TimeInterval = 1.5
    /// After selecting the tab, how long to wait before checking that it stays selected.
    private static let settleDelay: TimeInterval = 0.2

    let kind: TerminalKind
    let tty: String
    private let bundleIdentifier: String
    private let script: TerminalAppleScript
    /// The process keystrokes are posted to; set when the tab is focused.
    private var pid: pid_t?
    private var previousFront: PreviousFront?
    /// When this terminal was in front: the tty of the tab (or pane) the user was on.
    private var previousTTY: String?

    var terminalName: String { kind.displayName }
    var timeoutError: Error { ScriptedTerminalError.timedOut(terminalName) }
    let postsKeyEvents = true

    init(kind: TerminalKind, tty: String) {
        precondition(kind.isFoundByTTY, "a scripted driver drives iTerm2 or Terminal")
        self.kind = kind
        self.tty = tty
        bundleIdentifier = kind.bundleIdentifier ?? ""
        script = TerminalAppleScript(terminalName: kind.displayName)
        _ = AX.boundCalls
    }

    // MARK: TerminalDriver

    func focusSession(deadline: Date) throws {
        let running = try runningApplication()
        pid = running.processIdentifier
        rememberPreviousFront(terminalPid: running.processIdentifier)
        guard let source = TerminalScripts.focusSource(kind: kind, tty: tty) else { throw ScriptedTerminalError.sessionNotFound(terminalName) }
        guard Date() < deadline else { throw timeoutError }
        switch TerminalScripts.focusOutcome(try run(source)) {
        case .focused:
            break
        case .notRunning:
            throw ScriptedTerminalError.notRunning(terminalName)
        case .matches(0):
            throw ScriptedTerminalError.sessionNotFound(terminalName)
        case .matches:
            throw ScriptedTerminalError.duplicateSessions(terminalName)
        case .unexpected:
            throw ScriptedTerminalError.unexpectedAnswer(terminalName)
        }
        running.activate()
        let app = AX.application(pid: running.processIdentifier)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        try waitUntilOnSession(deadline: deadline)
    }

    func verifyFocus() throws -> String? {
        guard try isOnSession() else { throw ScriptedTerminalError.focusLost(terminalName) }
        return nil
    }

    func typeText(_ text: String) throws {
        KeyPoster.typeText(text, to: try targetPid())
    }

    func pressReturn() throws {
        KeyPoster.pressKey(KeyPoster.returnKey, to: try targetPid())
    }

    /// Another app: activated again. This terminal: its tab that was in front is selected again,
    /// with the same script that found the session's (it raises that tab's window).
    func restorePreviousFocus() {
        guard let previousFront, let pid, AX.isFrontmost(AX.application(pid: pid)) else { return }
        guard previousFront.isApp(pid: pid) else {
            previousFront.reactivateApp()
            return
        }
        guard let previousTTY, previousTTY != tty, let source = TerminalScripts.focusSource(kind: kind, tty: previousTTY) else { return }
        _ = try? run(source)
    }

    // MARK: Focus

    /// What was in front, and, when it was this terminal, the tty of its front tab (read only).
    private func rememberPreviousFront(terminalPid: pid_t) {
        previousFront = PreviousFront.capture()
        guard previousFront?.isApp(pid: terminalPid) == true, let source = TerminalScripts.frontSource(kind: kind),
              case .front(let frontTTY, _) = TerminalScripts.frontState((try? run(source)) ?? "")
        else { return }
        previousTTY = frontTTY
    }

    /// Activation takes a moment; then the tab must still be the front one a little later.
    private func waitUntilOnSession(deadline: Date) throws {
        let timeout = min(Self.activationTimeout, max(deadline.timeIntervalSinceNow, 0))
        var scriptError: Error?
        let isOn = AX.waitUntil(timeout: timeout) {
            do {
                return try isOnSession()
            } catch {
                scriptError = error
                return true
            }
        }
        if let scriptError { throw scriptError }
        guard isOn else { throw ScriptedTerminalError.couldNotActivate(terminalName) }
        Thread.sleep(forTimeInterval: Self.settleDelay)
        guard try isOnSession() else { throw ScriptedTerminalError.couldNotActivate(terminalName) }
    }

    /// The app that was focused is still running and frontmost (Accessibility), AppleScript says its
    /// front window's selected tab or pane is on the tty, and that window has keyboard focus.
    private func isOnSession() throws -> Bool {
        let running = try runningApplication()
        guard pid == running.processIdentifier else { return false }
        let app = AX.application(pid: running.processIdentifier)
        guard AX.isFrontmost(app), let source = TerminalScripts.frontSource(kind: kind) else { return false }
        let state = TerminalScripts.frontState(try run(source))
        if state == .notRunning { throw ScriptedTerminalError.notRunning(terminalName) }
        return TerminalScripts.isOnSession(state, tty: tty, focusedWindowTitle: AX.focusedWindowTitle(of: app))
    }

    private func runningApplication() throws -> NSRunningApplication {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) else {
            throw ScriptedTerminalError.notRunning(terminalName)
        }
        return running
    }

    private func targetPid() throws -> pid_t {
        guard let pid else { throw ScriptedTerminalError.notRunning(terminalName) }
        return pid
    }

    private func run(_ source: String) throws -> String {
        try script.run(source)
    }
}

/// Terminal.app: tabs inside windows, each with its tty.
final class AppleTerminalDriver: ScriptedTerminalDriver {
    init(tty: String) {
        super.init(kind: .terminal, tty: tty)
    }
}
