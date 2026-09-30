import AppKit
import ApplicationServices
import GearShiftCore

enum KeyPosterError: Error, CustomStringConvertible {
    case inputHeld

    var description: String {
        switch self {
        case .inputHeld: "release the keys/mouse and shift again"
        }
    }
}

/// Posts keystrokes to one process, the way every terminal driver types: Unicode string events,
/// one character per event, from a private event source, with explicit flags.
enum KeyPoster {
    /// Characters per key event. One is the safest: every character is its own keystroke, as if
    /// typed. Claude Code and Warp also take a burst of up to `maxUnitsPerEvent`.
    static let charactersPerEvent = 1
    /// Lets the typed text land before Return submits it.
    static let returnDelay: TimeInterval = 0.15
    static let returnKey: CGKeyCode = 36

    /// Between key events of one line.
    private static let keyEventDelay: TimeInterval = 0.01
    /// `CGEventKeyboardSetUnicodeString` drops text beyond about 20 UTF-16 units per event.
    private static let maxUnitsPerEvent = 20
    private static let heldModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]

    /// A held modifier would turn the typed keys into shortcuts, and a held mouse button means the
    /// user is in the middle of something (e.g. dragging a tab).
    static func checkNoInputHeld() throws {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let isButtonDown = CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
        guard flags.isDisjoint(with: heldModifiers), !isButtonDown else { throw KeyPosterError.inputHeld }
    }

    /// Unicode string events type the text whatever the keyboard layout.
    static func typeText(_ text: String, to pid: pid_t) {
        for chunk in KeyChunks.chunks(of: text, charactersPerEvent: charactersPerEvent, maxUnitsPerEvent: maxUnitsPerEvent) {
            post(keyCode: 0, flags: [], unicode: chunk, to: pid)
            Thread.sleep(forTimeInterval: keyEventDelay)
        }
    }

    static func pressKey(_ key: CGKeyCode, flags: CGEventFlags = [], to pid: pid_t) {
        post(keyCode: key, flags: flags, unicode: nil, to: pid)
    }

    /// Posted to that process only, from a private event source, with explicit flags: nothing
    /// reaches another app, and no modifier state leaks in.
    private static func post(keyCode: CGKeyCode, flags: CGEventFlags, unicode: [UniChar]?, to pid: pid_t) {
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = flags
            if let unicode {
                event.keyboardSetUnicodeString(stringLength: unicode.count, unicodeString: unicode)
            }
            event.postToPid(pid)
        }
    }
}

/// The permissions GearShift asks for: Accessibility (to read windows and post keys) and, for
/// iTerm2 and Terminal, Automation (to find the session by tty through AppleScript: iTerm2 is
/// written to in the background, Terminal's tab is selected).
enum Permissions {
    static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    /// Whether the user said no to GearShift controlling that app (without asking again). Unknown
    /// (not asked yet, or the app isn't running) counts as not denied.
    static func isAutomationDenied(bundleIdentifier: String) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let address = target.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, false)
        return status == OSStatus(errAEEventNotPermitted)
    }

    private static func open(_ link: String) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Accessibility reads shared by the terminal drivers. Every call gives up after 1 s instead of the
/// default 6 s.
enum AX {
    private static let pollInterval: TimeInterval = 0.05

    static let boundCalls: Void = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1)
    }()

    static func application(pid: pid_t) -> AXUIElement {
        _ = boundCalls
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        return app
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let array = value(element, attribute) as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? (item as! AXUIElement) : nil
        }
    }

    static func title(of window: AXUIElement) -> String {
        string(window, kAXTitleAttribute) ?? ""
    }

    static func isFrontmost(_ app: AXUIElement) -> Bool {
        (value(app, kAXFrontmostAttribute) as? Bool) ?? false
    }

    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        guard let window = value(app, kAXFocusedWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        return (window as! AXUIElement)
    }

    static func focusedWindowTitle(of app: AXUIElement) -> String? {
        focusedWindow(of: app).map(title(of:))
    }

    /// Polls every 50 ms; true as soon as the condition holds, false at the timeout.
    static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if condition() { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }
}
