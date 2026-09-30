import AppKit
import ApplicationServices
import GearShiftCore

enum WarpDriverError: Error, CustomStringConvertible {
    case warpNotRunning
    case couldNotActivate
    case noWindows
    case windowNotRaisable
    case tabNotFound(String)
    case duplicateTabs(String)
    case tooManyTabs
    case tabNotSettled(String)
    case focusLost
    case timedOut

    var description: String {
        switch self {
        case .warpNotRunning: "Warp isn't running"
        case .couldNotActivate: "couldn't bring Warp to the front"
        case .noWindows: "no Warp windows found"
        case .windowNotRaisable: "couldn't check every Warp window (one is minimized?): shift again"
        case .tabNotFound(let title): "open \(title)'s tab in Warp"
        case .duplicateTabs(let title): "two Warp tabs show '\(title)': close or /rename one"
        case .tooManyTabs: "a Warp window has too many tabs to check"
        case .tabNotSettled(let title): "\(title)'s tab didn't settle in Warp: shift again"
        case .focusLost: "Warp lost focus: shift again"
        case .timedOut: "Warp took too long: shift again"
        }
    }
}

/// Drives Warp through Accessibility: finds a session's tab by window title and types into it.
/// Warp has no way to type into a tab in the background, so it's brought to the front; afterwards
/// the app that was in front comes back, and if that was Warp, its window and tab too.
/// Blocking, and not thread-safe: use one per shift, from one background queue.
final class WarpDriver: TerminalDriver {
    static let bundleIdentifier = TerminalKind.warp.bundleIdentifier!

    private static let pollInterval: TimeInterval = 0.05
    /// Warp updated the window title within 600 ms of a tab switch when measured.
    private static let tabSwitchTimeout: TimeInterval = 0.6
    /// Between the switches that put a window back on its tab, which aren't checked one by one.
    private static let restoreSwitchDelay: TimeInterval = 0.08
    private static let activationTimeout: TimeInterval = 1.5
    /// After finding the tab, how long to wait before checking that its title stays put.
    private static let settleDelay: TimeInterval = 0.3
    private static let settleTimeout: TimeInterval = 1.5
    private static let rightBracketKey: CGKeyCode = 0x1E
    private static let leftBracketKey: CGKeyCode = 0x21

    private enum Direction {
        case next, previous
    }

    /// The session's title, as its Warp tab shows it after the glyph.
    let sessionTitle: String
    /// The Warp process keystrokes are posted to; set when Warp is brought to the front.
    private var warpPid: pid_t?
    private var previousFront: PreviousFront?
    /// When Warp was in front: its focused window then.
    private var previousWindow: AXUIElement?
    /// The session's window, and how many `Switch to Next Tab` it took from the tab it was on.
    private var sessionTab: (window: AXUIElement, switchesFromStart: Int)?

    let terminalName = TerminalKind.warp.displayName
    let timeoutError: Error = WarpDriverError.timedOut
    let postsKeyEvents = true

    init(sessionTitle: String) {
        self.sessionTitle = sessionTitle
        _ = AX.boundCalls
    }

    // MARK: TerminalDriver

    func focusSession(deadline: Date) throws {
        try focusTab(titled: sessionTitle, deadline: deadline)
    }

    /// Warp's readiness is judged by the glyph in this title.
    func verifyFocus() throws -> String? {
        try focusedTitle(matching: sessionTitle)
    }

    /// Another app (GearShift included): activated again. Warp: its window that was in front is
    /// raised again, or, when that's the session's window, switched back to the tab it was on (the
    /// search left every other window on its own tab). Only while Warp is still in front.
    func restorePreviousFocus() {
        guard let previousFront, let warpPid, let app = try? warpApplication(), isFrontmost(app) else { return }
        guard previousFront.isApp(pid: warpPid) else {
            previousFront.reactivateApp()
            return
        }
        guard let previousWindow else { return }
        if let sessionTab, CFEqual(sessionTab.window, previousWindow) {
            let isOnSessionWindow = focusedWindow(of: app).map { CFEqual($0, sessionTab.window) } ?? false
            if isOnSessionWindow {
                try? switchTabs(.previous, times: sessionTab.switchesFromStart, in: app)
            }
        } else {
            _ = raise(previousWindow, in: app)
        }
    }

    // MARK: Finding the tab

    /// Brings Warp to the front with the session's tab active. Every tab of every window is looked
    /// at, and each window is put back on the tab it was on; the session's tab is then selected only
    /// if it's the only one showing that title, and once its title has settled.
    func focusTab(titled sessionTitle: String, deadline: Date) throws {
        let app = try activateWarp()
        let windows = try titledWindows(of: app)
        var searches: [TabSearch] = []
        for window in windows {
            try check(deadline)
            guard raise(window, in: app) else { throw WarpDriverError.windowNotRaisable }
            searches.append(try search(window, of: app, for: sessionTitle, deadline: deadline))
        }
        switch TabSearch.decide(searches) {
        case .found(let index, let offset):
            guard raise(windows[index], in: app) else { throw WarpDriverError.windowNotRaisable }
            try switchTabs(.next, times: offset, in: app)
            sessionTab = (windows[index], offset)
            try waitUntilSettled(on: sessionTitle, in: app, deadline: deadline)
        case .notFound:
            throw WarpDriverError.tabNotFound(sessionTitle)
        case .duplicate:
            throw WarpDriverError.duplicateTabs(sessionTitle)
        case .incomplete:
            throw WarpDriverError.tooManyTabs
        }
    }

    /// Cycles through one window's tabs, then back to the one it started on.
    private func search(_ window: AXUIElement, of app: AXUIElement, for sessionTitle: String, deadline: Date) throws -> TabSearch {
        var search = TabSearch(target: sessionTitle)
        var current: String? = title(of: window)
        var switchesMade = 0
        while search.observe(current) == .next {
            if Date() >= deadline {
                try switchTabs(.previous, times: switchesMade, in: app)
                throw WarpDriverError.timedOut
            }
            let previous = current ?? ""
            try switchTab(.next, in: app)
            switchesMade += 1
            current = waitForTitleChange(of: window, from: previous)
        }
        try switchTabs(.previous, times: search.pressesBackToStart, in: app)
        return search
    }

    /// The new title, or nil when it didn't change within the timeout (the window has one tab, or
    /// the next tab shows the same). A title that hasn't changed yet is never passed on as the next
    /// tab's. Titles are compared without the glyph, which animates on its own.
    private func waitForTitleChange(of window: AXUIElement, from previous: String) -> String? {
        let before = WarpTitle.normalized(previous)
        var current = previous
        let hasChanged = waitUntil(timeout: Self.tabSwitchTimeout) {
            current = title(of: window)
            return WarpTitle.normalized(current) != before
        }
        return hasChanged ? current : nil
    }

    /// Two identical reads, both showing the session, a while after the switch: the title isn't a
    /// leftover of the previous tab.
    private func waitUntilSettled(on sessionTitle: String, in app: AXUIElement, deadline: Date) throws {
        Thread.sleep(forTimeInterval: Self.settleDelay)
        let hasSettled = waitUntil(timeout: min(Self.settleTimeout, max(deadline.timeIntervalSinceNow, 0))) {
            guard let first = focusedWindowTitle(of: app), WarpTitle.matches(windowTitle: first, sessionTitle: sessionTitle) else {
                return false
            }
            Thread.sleep(forTimeInterval: Self.pollInterval)
            return focusedWindowTitle(of: app) == first
        }
        guard hasSettled else { throw WarpDriverError.tabNotSettled(sessionTitle) }
    }

    private func switchTabs(_ direction: Direction, times: Int, in app: AXUIElement) throws {
        for _ in 0..<max(times, 0) {
            try switchTab(direction, in: app)
            Thread.sleep(forTimeInterval: Self.restoreSwitchDelay)
        }
    }

    /// Through the Tab menu, which acts on the key window; Cmd-Shift-] / [ if the item is missing.
    private func switchTab(_ direction: Direction, in app: AXUIElement) throws {
        let itemTitle = direction == .next ? "Switch to Next Tab" : "Switch to Previous Tab"
        if let item = menuItem(of: app, menu: "Tab", item: itemTitle),
           AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
            return
        }
        guard isFrontmost(app) else { throw WarpDriverError.focusLost }
        try pressKey(direction == .next ? Self.rightBracketKey : Self.leftBracketKey, flags: [.maskCommand, .maskShift])
    }

    // MARK: Typing

    /// The title of Warp's focused window, provided Warp is frontmost and that window shows the
    /// session: checked right before any keystroke, since the user may have clicked elsewhere.
    func focusedTitle(matching sessionTitle: String) throws -> String {
        let app = try warpApplication()
        guard isFrontmost(app), let windowTitle = focusedWindowTitle(of: app),
              WarpTitle.matches(windowTitle: windowTitle, sessionTitle: sessionTitle)
        else { throw WarpDriverError.focusLost }
        return windowTitle
    }

    func typeText(_ text: String) throws {
        KeyPoster.typeText(text, to: try targetPid())
    }

    func pressReturn() throws {
        try pressKey(KeyPoster.returnKey)
    }

    private func pressKey(_ key: CGKeyCode, flags: CGEventFlags = []) throws {
        KeyPoster.pressKey(key, flags: flags, to: try targetPid())
    }

    private func targetPid() throws -> pid_t {
        guard let warpPid else { throw WarpDriverError.warpNotRunning }
        return warpPid
    }

    // MARK: Application and windows

    /// Warp as found by `focusTab`; a Warp that restarted since then is another process, and
    /// counts as lost focus.
    private func warpApplication() throws -> AXUIElement {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else {
            throw WarpDriverError.warpNotRunning
        }
        guard warpPid == nil || warpPid == running.processIdentifier else { throw WarpDriverError.focusLost }
        return AX.application(pid: running.processIdentifier)
    }

    private func activateWarp() throws -> AXUIElement {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).first else {
            throw WarpDriverError.warpNotRunning
        }
        warpPid = running.processIdentifier
        let app = try warpApplication()
        rememberPreviousFront(of: app, warpPid: running.processIdentifier)
        running.activate()
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        guard waitUntil(timeout: Self.activationTimeout, { isFrontmost(app) }) else {
            throw WarpDriverError.couldNotActivate
        }
        return app
    }

    /// What was in front, and, when it was Warp, its focused window.
    private func rememberPreviousFront(of app: AXUIElement, warpPid: pid_t) {
        previousFront = PreviousFront.capture()
        if previousFront?.isApp(pid: warpPid) == true {
            previousWindow = focusedWindow(of: app)
        }
    }

    /// Windows on another Space are listed only once the switch to Warp's Space has happened, so
    /// this waits for them. Warp also has an untitled helper window, which is skipped.
    private func titledWindows(of app: AXUIElement) throws -> [AXUIElement] {
        var windows: [AXUIElement] = []
        _ = waitUntil(timeout: Self.activationTimeout) {
            windows = elements(app, kAXWindowsAttribute).filter {
                string($0, kAXRoleAttribute) == kAXWindowRole && !title(of: $0).isEmpty
            }
            return !windows.isEmpty
        }
        guard !windows.isEmpty else { throw WarpDriverError.noWindows }
        return windows
    }

    /// Next Tab acts on the key window, so the window must actually take focus first.
    private func raise(_ window: AXUIElement, in app: AXUIElement) -> Bool {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        return waitUntil(timeout: Self.tabSwitchTimeout) {
            focusedWindow(of: app).map { CFEqual($0, window) } ?? false
        }
    }

    private func isFrontmost(_ app: AXUIElement) -> Bool {
        AX.isFrontmost(app)
    }

    private func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        AX.focusedWindow(of: app)
    }

    private func focusedWindowTitle(of app: AXUIElement) -> String? {
        AX.focusedWindowTitle(of: app)
    }

    private func menuItem(of app: AXUIElement, menu menuTitle: String, item itemTitle: String) -> AXUIElement? {
        guard let bar = value(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        let barItem = elements(bar as! AXUIElement, kAXChildrenAttribute).first { string($0, kAXTitleAttribute) == menuTitle }
        let menus = barItem.map { elements($0, kAXChildrenAttribute) } ?? []
        return menus.lazy
            .flatMap { self.elements($0, kAXChildrenAttribute) }
            .first { self.string($0, kAXTitleAttribute) == itemTitle }
    }

    private func check(_ deadline: Date) throws {
        guard Date() < deadline else { throw WarpDriverError.timedOut }
    }

    // MARK: AX helpers

    private func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        AX.value(element, attribute)
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        AX.string(element, attribute)
    }

    private func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        AX.elements(element, attribute)
    }

    private func title(of window: AXUIElement) -> String {
        AX.title(of: window)
    }

    /// Polls every 50 ms; true as soon as the condition holds, false at the timeout.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        AX.waitUntil(timeout: timeout, condition)
    }
}
