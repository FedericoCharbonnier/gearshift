import Foundation
import GearShiftCore
import SwiftUI

/// App state: the connected sessions and the selected one, the gear each was shifted into, the
/// token meter and settings. Shifting drives the session's terminal through a `TerminalDriver`.
@MainActor
final class AppModel: ObservableObject {
    static let defaultHint = "tap a gear to shift"
    static let noSessionHint = "run /gearshift in a Claude session"
    static let accessibilityHint = "grant Accessibility to GearShift, then shift again"

    @Published private(set) var config: GearConfig
    /// Newest registration first.
    @Published private(set) var sessions: [SessionRecord] = []
    @Published private(set) var selectedSessionId: String? {
        didSet { if selectedSessionId != oldValue { invalidateMeter() } }
    }
    @Published private(set) var isAccessibilityTrusted: Bool
    /// The terminal ("iTerm", "Terminal") GearShift was last refused Automation for, until a shift
    /// into it works: the footer then offers the Automation settings.
    @Published private(set) var automationDeniedApp: String?
    @Published private(set) var tokensPerMinute = 0
    @Published private(set) var hint = AppModel.noSessionHint
    @Published private(set) var redlineCount = 0
    @Published private(set) var isRedlining = false
    /// Session id → title, last prompt, model and branch from its transcript.
    @Published private var sessionInfos: [String: SessionInfo] = [:]
    /// Session id → the gear it was last shifted into. Claude Code can't be asked, so this is only
    /// what GearShift did, and it is forgotten on quit.
    @Published private var gearMemory: [String: GearMemory] = [:]
    @Published private var pendingShift: PendingShift?

    private let store: GearConfigStore
    /// Touched only on `sessionQueue`.
    private let poller: SessionPoller
    private let sessionQueue = DispatchQueue(label: "gearshift.sessions")
    private var isPollingSessions = false
    /// The newest registration seen; a later one is a fresh `/gearshift`.
    private var newestRegistration: Date?
    /// Runs one shift at a time; each makes its own terminal driver.
    private let shiftQueue = DispatchQueue(label: "gearshift.shift")
    private var hasPromptedForAccessibility = false
    /// Touched only on `meterQueue`: reading a transcript can take a noticeable moment.
    private let meter = TokenMeter()
    private let meterQueue = DispatchQueue(label: "gearshift.meter")
    private var isPollingMeter = false
    /// Bumped whenever the selected session changes, so a poll started before then is dropped.
    private var meterGeneration = 0
    private let sounds = SoundFX()
    private var kickUntil: Date?
    private var hintReset: Task<Void, Never>?
    private var timers: [Timer] = []

    init(store: GearConfigStore = GearConfigStore(), registry: SessionRegistry = SessionRegistry()) {
        self.store = store
        poller = SessionPoller(registry: registry)
        config = store.load()
        isAccessibilityTrusted = Permissions.isAccessibilityTrusted(prompt: false)
        pollSessions()
        startTimers()
    }

    // MARK: Derived state

    var selectedSession: SessionRecord? {
        sessions.first { $0.sessionId == selectedSessionId }
    }

    /// The engaged gear of the selected session: neutral until GearShift shifts it, and while a
    /// shift that stopped half way left it unknown.
    var gear: Gear {
        guard case .engaged(let gear) = selectedSessionId.flatMap({ gearMemory[$0] }) else { return .neutral }
        return gear
    }

    var isGearUnknown: Bool {
        selectedSessionId.flatMap { gearMemory[$0] } == .unknown
    }

    /// Where the knob rests: on the gear being shifted into while that shift is in flight.
    var knobGear: Gear {
        if let pendingShift, pendingShift.sessionId == selectedSessionId { return pendingShift.gear }
        return gear
    }

    var hasSession: Bool { selectedSession != nil }
    var canShift: Bool { hasSession && pendingShift == nil }

    /// The title Claude Code shows, which is also in its Warp tab's title; for display only, the
    /// folder name while the transcript has none. Shifting never looks for the folder name.
    func sessionTitle(for session: SessionRecord) -> String {
        claudeTitle(for: session) ?? folderName(of: session)
    }

    /// The title from the transcript, if it has one yet.
    func claudeTitle(for session: SessionRecord) -> String? {
        sessionInfos[session.sessionId]?.title
    }

    /// What the session is called on screen: the user's nickname, else its title (or folder).
    /// Display only; shifting never looks for it.
    func displayName(for session: SessionRecord) -> String {
        session.nickname ?? sessionTitle(for: session)
    }

    /// `gearshift · main · opus 5.5`, plus `untitled` while a Warp session's transcript has no title:
    /// `/rename` fixes that. Sessions in iTerm2 and Terminal are found by tty, so it doesn't matter.
    func sessionDetail(for session: SessionRecord) -> String {
        let info = sessionInfos[session.sessionId]
        let isUntitledInWarp = info?.title == nil && !TerminalStrategy.isFoundByTTY(session)
        let parts = [
            folderName(of: session),
            info?.gitBranch,
            info?.model.map(ModelName.display),
            isUntitledInWarp ? "untitled" : nil,
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// The session picker's detail line: the terminal first, e.g. `Terminal · gearshift · main · opus 5.5`.
    func pickerDetail(for session: SessionRecord) -> String {
        "\(terminalName(of: session)) · \(sessionDetail(for: session))"
    }

    /// Records from before terminals were recorded are Warp's.
    func terminalName(of session: SessionRecord) -> String {
        let kind = session.terminal ?? .warp
        return kind == .other ? session.termProgram ?? kind.displayName : kind.displayName
    }

    func lastPrompt(for session: SessionRecord) -> String? {
        sessionInfos[session.sessionId]?.lastPrompt
    }

    func color(for session: SessionRecord) -> Color {
        Color(hex: SessionColor.hex(for: session))
    }

    private func folderName(of session: SessionRecord) -> String {
        URL(fileURLWithPath: session.cwd).lastPathComponent
    }

    var readoutTitle: String {
        isGearUnknown ? "?" : config.gears[gear]?.displayName ?? ""
    }

    /// One command per line: the readout column is too narrow to wrap `/model x · /effort y` well.
    var readoutCommand: String {
        guard !isGearUnknown, let setting = config.gears[gear] else { return "" }
        return ShiftCommands.commands(for: setting)?.map(\.line).joined(separator: "\n") ?? "invalid model"
    }

    /// Where the tach needle heads: a short kick after a shift, then the live rate (idle ~900).
    var needleTarget: Double {
        if let kickUntil, kickUntil > Date() { return gear.shiftKick }
        return tokensPerMinute > 0 ? min(Double(tokensPerMinute), 8000) : 900
    }

    // MARK: Actions

    func selectSession(_ sessionId: String) {
        selectedSessionId = sessionId
    }

    /// Checks here what can be checked without the terminal, then finds the session's tab and types
    /// the gear's commands on `shiftQueue`. New shifts are ignored until that finishes.
    func shift(to newGear: Gear) {
        guard pendingShift == nil else { return }
        guard let session = selectedSession else {
            showHint(Self.noSessionHint)
            return
        }
        guard isAccessibilityGranted(), let setting = config.gears[newGear] else { return }
        guard let commands = ShiftCommands.commands(for: setting) else {
            showHint(ShiftRefusal.invalidModel(setting.model).description)
            return
        }
        pendingShift = PendingShift(sessionId: session.sessionId, gear: newGear)
        // A draft in that session's input would be submitted along with the command.
        showHint("shifting \(displayName(for: session)): make sure that session's input is empty", resets: false)
        let request = ShiftRequest(sessionId: session.sessionId, commands: commands, returnsToPreviousApp: config.returnsToPreviousApp)
        let (poller, sessionQueue) = (self.poller, self.sessionQueue)
        let scriptedTerminal = session.terminal.flatMap { $0.isFoundByTTY ? $0 : nil }
        shiftQueue.async {
            let result = Result { try request.perform(poller: poller, sessionQueue: sessionQueue) }
            let automation = scriptedTerminal.map { Self.automationState(of: $0, after: result) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.finishShift(to: newGear, setting: setting, sessionId: session.sessionId, result: result)
                    if let automation { self.updateAutomationHint(automation) }
                }
            }
        }
    }

    func updateSettings(gears: [Gear: GearSetting], isMuted: Bool, keepsOnTop: Bool, returnsToPreviousApp: Bool) {
        config.gears = gears
        config.isMuted = isMuted
        config.keepsOnTop = keepsOnTop
        config.returnsToPreviousApp = returnsToPreviousApp
        saveConfig()
    }

    func openAccessibilitySettings() {
        Permissions.openAccessibilitySettings()
    }

    func openAutomationSettings() {
        Permissions.openAutomationSettings()
    }

    // MARK: Shifting

    private func finishShift(to newGear: Gear, setting: GearSetting, sessionId: String, result: Result<Void, Error>) {
        pendingShift = nil
        switch result {
        case .success:
            gearMemory[sessionId] = .engaged(newGear)
            showHint(restingHint)
            kick()
            if !config.isMuted {
                sounds.play(shiftTo: setting)
            }
            if newGear == .five {
                redline()
            }
        case .failure(let error):
            if let failure = error as? ShiftFailure, failure.isGearUnknown {
                gearMemory[sessionId] = .unknown
            }
            showHint("\(error)")
        }
    }

    /// Whether GearShift may send Apple Events to that terminal, after a shift into it: denied when
    /// AppleScript said so, or macOS says the user turned it off. Runs on `shiftQueue`.
    nonisolated private static func automationState(of terminal: TerminalKind, after result: Result<Void, Error>) -> AutomationState {
        let isDenied: Bool
        switch result {
        case .success:
            isDenied = false
        case .failure(let error):
            isDenied = Self.isAutomationDenial(error)
                || terminal.bundleIdentifier.map(Permissions.isAutomationDenied(bundleIdentifier:)) ?? false
        }
        return AutomationState(app: terminal.displayName, isDenied: isDenied)
    }

    nonisolated private static func isAutomationDenial(_ error: Error) -> Bool {
        if case ScriptedTerminalError.automationDenied = error { return true }
        return false
    }

    /// Shows the Automation button while that terminal refuses GearShift. The hint already says what
    /// to allow, from the shift's error.
    private func updateAutomationHint(_ state: AutomationState) {
        if state.isDenied {
            automationDeniedApp = state.app
        } else if automationDeniedApp == state.app {
            automationDeniedApp = nil
        }
    }

    /// Asks macOS once per launch to prompt for the permission; after that only the hint shows.
    private func isAccessibilityGranted() -> Bool {
        let isTrusted = Permissions.isAccessibilityTrusted(prompt: !hasPromptedForAccessibility)
        if !isTrusted {
            hasPromptedForAccessibility = true
            showHint(Self.accessibilityHint)
        }
        if isAccessibilityTrusted != isTrusted {
            isAccessibilityTrusted = isTrusted
        }
        return isTrusted
    }

    // MARK: Sessions

    /// Reads the registry and transcripts on `sessionQueue` and publishes them here. A tick is skipped
    /// while the previous poll is still running.
    private func pollSessions() {
        let isTrusted = Permissions.isAccessibilityTrusted(prompt: false)
        if isAccessibilityTrusted != isTrusted {
            isAccessibilityTrusted = isTrusted
        }
        guard !isPollingSessions else { return }
        isPollingSessions = true
        let poller = self.poller
        sessionQueue.async {
            let snapshot = poller.poll()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finishSessionPoll(snapshot) }
            }
        }
    }

    private func finishSessionPoll(_ snapshot: SessionSnapshot) {
        isPollingSessions = false
        if sessions != snapshot.sessions {
            sessions = snapshot.sessions
        }
        if sessionInfos != snapshot.infos {
            sessionInfos = snapshot.infos
        }
        updateSelection()
        let liveIds = Set(sessions.map(\.sessionId))
        if gearMemory.keys.contains(where: { !liveIds.contains($0) }) {
            gearMemory = gearMemory.filter { liveIds.contains($0.key) }
        }
        if hint == Self.defaultHint || hint == Self.noSessionHint, hint != restingHint {
            hint = restingHint
        }
    }

    /// A fresh `/gearshift` selects its session only if nothing is selected or it is the selected
    /// session; a shift must never land in a session the user didn't pick. When the selected
    /// session ends, the newest remaining one is selected.
    private func updateSelection() {
        let result = SessionSelection.update(selected: selectedSessionId, newestSeen: newestRegistration, sessions: sessions)
        newestRegistration = result.newestSeen
        if selectedSessionId != result.selected {
            selectedSessionId = result.selected
        }
        if let connectedId = result.connected, pendingShift == nil,
           let connected = sessions.first(where: { $0.sessionId == connectedId }) {
            showHint("\(displayName(for: connected)) connected")
        }
    }

    // MARK: Meter

    /// Added in `.common` mode so they keep firing while a menu is open or the window is dragged.
    private func startTimers() {
        let sessions = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSessions() }
        }
        let meter = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollMeter() }
        }
        timers = [sessions, meter]
        for timer in timers {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Reads the selected transcript on `meterQueue` and publishes the rate back here. A tick is
    /// skipped while the previous poll is still running, so polls never pile up; a result for a
    /// session that's no longer selected is dropped.
    private func pollMeter() {
        guard !isPollingMeter else { return }
        isPollingMeter = true
        let source = selectedSession.map { TokenMeter.Source.claude(URL(fileURLWithPath: $0.transcriptPath)) }
        let generation = meterGeneration
        let meter = self.meter
        meterQueue.async {
            let rate = meter.poll(source: source)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finishMeterPoll(rate: rate, generation: generation) }
            }
        }
    }

    private func finishMeterPoll(rate: Int, generation: Int) {
        isPollingMeter = false
        guard generation == meterGeneration, tokensPerMinute != rate else { return }
        tokensPerMinute = rate
    }

    private func invalidateMeter() {
        meterGeneration += 1
        if tokensPerMinute != 0 {
            tokensPerMinute = 0
        }
    }

    // MARK: Effects

    private func kick() {
        kickUntil = Date().addingTimeInterval(0.7)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            objectWillChange.send()
        }
    }

    private func redline() {
        redlineCount += 1
        isRedlining = true
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            isRedlining = false
        }
    }

    /// A hint that `resets` goes back to the default after 4 s; one that doesn't stays until the
    /// next hint, e.g. while a shift is in flight.
    private func showHint(_ text: String, resets: Bool = true) {
        hint = text
        hintReset?.cancel()
        guard resets else { return }
        hintReset = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            hint = restingHint
        }
    }

    /// What the footer says when nothing else is going on.
    private var restingHint: String {
        sessions.isEmpty ? Self.noSessionHint : Self.defaultHint
    }

    private func saveConfig() {
        do {
            try store.save(config)
        } catch {
            showHint("couldn't save settings: \(error.localizedDescription)")
        }
    }
}

private struct AutomationState {
    let app: String
    let isDenied: Bool
}

private struct PendingShift: Equatable {
    let sessionId: String
    let gear: Gear
}

/// What GearShift knows about a session's gear.
private enum GearMemory: Equatable {
    case engaged(Gear)
    /// A shift stopped after sending something: the model or effort may have changed.
    case unknown
}
