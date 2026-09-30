import Foundation
import GearShiftCore

/// One shift, run on `AppModel.shiftQueue`: finds the session's tab (by title in Warp, by tty in
/// iTerm2 and Terminal) and types the gear's commands, one at a time, each only once the previous
/// one shows up in the transcript. Everything that could send keystrokes to the wrong place is
/// checked again right before each keystroke. iTerm2 is written to in the background; Warp and
/// Terminal are brought to the front, and, with `returnsToPreviousApp`, sent back afterwards.
struct ShiftRequest {
    /// The whole shift, up to the first keystroke of each command; after that, nothing is typed.
    static let overallTimeout: TimeInterval = 10
    /// How long a command may take to show up in the transcript after Return.
    static let confirmationTimeout: TimeInterval = 3
    static let confirmationPollInterval: TimeInterval = 0.1
    /// Between one confirmed command and the next.
    static let minimumLineDelay: TimeInterval = 0.1
    /// Enough of the transcript's end to hold the last assistant message and what followed it.
    static let transcriptTailBytes: UInt64 = 1 << 20

    let sessionId: String
    let commands: [ShiftCommand]
    /// After typing stops (success or failure), bring back what was in front before a terminal was
    /// focused. Otherwise focus stays in the terminal.
    let returnsToPreviousApp: Bool

    /// Registry and titles are read again first, so a `/rename` or an ended session from the last
    /// couple of seconds counts.
    func perform(poller: SessionPoller, sessionQueue: DispatchQueue) throws {
        let deadline = Date().addingTimeInterval(Self.overallTimeout)
        let (session, target) = try freshTarget(poller: poller, sessionQueue: sessionQueue)
        try checkReady(session, target: target, windowTitle: nil)
        let driver = Self.driver(for: target)
        defer {
            if returnsToPreviousApp {
                driver.restorePreviousFocus()
            }
        }
        try driver.focusSession(deadline: deadline)
        try type(into: session, target: target, driver: driver, deadline: deadline)
    }

    static func driver(for target: ShiftTarget.Resolved) -> TerminalDriver {
        switch target {
        case .warpTab(let title): WarpDriver(sessionTitle: title)
        case .ttyTab(.iterm, let tty): ITermDriver(tty: tty)
        case .ttyTab(_, let tty): AppleTerminalDriver(tty: tty)
        }
    }

    private func freshTarget(poller: SessionPoller, sessionQueue: DispatchQueue) throws -> (SessionRecord, ShiftTarget.Resolved) {
        let snapshot = sessionQueue.sync { poller.poll() }
        let target = try ShiftTarget.resolveTarget(sessionId: sessionId, titles: snapshot.titles, liveSessions: snapshot.sessions).get()
        guard let session = snapshot.sessions.first(where: { $0.sessionId == sessionId }) else { throw ShiftRefusal.sessionGone }
        return (session, target)
    }

    /// Types each command and presses Return, then waits for the transcript to record it. A failure
    /// part way says what landed, so the hint (and the gear shown) stay honest.
    private func type(into session: SessionRecord, target: ShiftTarget.Resolved, driver: TerminalDriver, deadline: Date) throws {
        var confirmed = 0
        for command in commands {
            var isTyped = false
            var isSubmitted = false
            do {
                if confirmed > 0 {
                    Thread.sleep(forTimeInterval: Self.minimumLineDelay)
                }
                guard Date() < deadline else { throw driver.timeoutError }
                try checkBeforeKeystroke(session, target: target, driver: driver)
                let tail = TranscriptTail(url: transcript(of: session), startingAtEnd: true)
                try driver.typeText(command.line)
                isTyped = true
                Thread.sleep(forTimeInterval: KeyPoster.returnDelay)
                try checkBeforeKeystroke(session, target: target, driver: driver)
                try driver.pressReturn()
                isSubmitted = true
                try awaitConfirmation(of: command, in: tail, target: target)
                confirmed += 1
            } catch {
                throw ShiftFailure(
                    reason: "\(error)", commands: commands, confirmed: confirmed,
                    typedUnsent: isTyped && !isSubmitted, submittedUnconfirmed: isSubmitted)
            }
        }
    }

    /// The keystroke would reach the session (a focused terminal: frontmost on the session's tab),
    /// the session is alive and idle, and, for key events, no key or button is held.
    private func checkBeforeKeystroke(_ session: SessionRecord, target: ShiftTarget.Resolved, driver: TerminalDriver) throws {
        let windowTitle = try driver.verifyFocus()
        try checkReady(session, target: target, windowTitle: windowTitle)
        if driver.postsKeyEvents {
            try KeyPoster.checkNoInputHeld()
        }
    }

    /// Warp: the title's glyph (once the tab is found) and pending tool calls. iTerm2 and
    /// Terminal: the transcript alone, which must show the turn over.
    private func checkReady(_ session: SessionRecord, target: ShiftTarget.Resolved, windowTitle: String?) throws {
        guard SessionRegistry.isProcessAlive(session.claudePid) else { throw ShiftRefusal.sessionGone }
        let lines = TranscriptTail.lastLines(of: transcript(of: session), maxBytes: Self.transcriptTailBytes)
        let refusal = switch target {
        case .warpTab: ShiftReadiness.refusal(windowTitle: windowTitle, transcriptLines: lines)
        case .ttyTab: ShiftReadiness.refusal(transcriptLines: lines)
        }
        if let refusal {
            throw refusal
        }
    }

    /// An untitled session's Warp tab was found by Claude Code's generic title, so an unconfirmed
    /// command may have gone to another untitled session; the hint says so. A tab found by tty is
    /// the session's own.
    private func awaitConfirmation(of command: ShiftCommand, in tail: TranscriptTail, target: ShiftTarget.Resolved) throws {
        let refusal = switch target {
        case .warpTab(let title): ShiftRefusal.unconfirmed(command.name, targetTitle: title)
        case .ttyTab: ShiftRefusal.notConfirmed(command.name)
        }
        let deadline = Date().addingTimeInterval(Self.confirmationTimeout)
        var lines: [String] = []
        while true {
            lines += tail.readNewLines()
            switch CommandConfirmation.find(command: command.name, args: command.args, inLines: lines) {
            case .confirmed:
                return
            case .emptyArgs:
                throw refusal
            case .notFound:
                guard Date() < deadline else { throw refusal }
                Thread.sleep(forTimeInterval: Self.confirmationPollInterval)
            }
        }
    }

    private func transcript(of session: SessionRecord) -> URL {
        URL(fileURLWithPath: session.transcriptPath)
    }
}
