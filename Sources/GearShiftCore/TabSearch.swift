import Foundation

/// Looks through every tab of one Warp window, one Next Tab switch at a time, recording which tabs
/// show the target session. It doesn't stop at a match: a second tab with the same title must be
/// noticed, so that nothing is typed into the wrong one.
///
/// Feed it the window title first, then after each switch the new title, or nil when the title
/// didn't change within the timeout (a window with one tab, or two neighbouring tabs showing the
/// same thing: either way nothing more can be learned there).
public struct TabSearch {
    public enum Step: Equatable {
        /// Switch to the next tab and observe again.
        case next
        /// This window is done.
        case done
    }

    public enum Decision: Equatable {
        /// Exactly one tab in all windows shows the session: `offset` Next Tab switches from where
        /// `window` started.
        case found(window: Int, offset: Int)
        case notFound
        /// More than one tab shows the session's title.
        case duplicate
        /// One match, but a window was cut short by the limit, so it may not be the only one.
        case incomplete
    }

    public static let defaultLimit = 30

    public let target: String
    /// The most Next Tab switches in one window.
    public let limit: Int
    /// Next Tab switches made so far (each `.next` is one).
    public private(set) var nextPresses = 0
    /// Offsets (Next Tab switches from the starting tab) of the tabs showing the session.
    public private(set) var matchOffsets: [Int] = []
    /// The number of tabs, once the titles have been seen to wrap around.
    public private(set) var cycleLength: Int?
    /// False when the limit stopped the search before the tabs wrapped.
    public private(set) var isComplete = false
    private var keys: [String] = []
    private var isDone = false

    public init(target: String, limit: Int = TabSearch.defaultLimit) {
        self.target = target
        self.limit = limit
    }

    /// The tabs have wrapped when the first two titles seen come round again, one after the other.
    public mutating func observe(_ windowTitle: String?) -> Step {
        guard !isDone else { return .done }
        guard let windowTitle else { return finish(isComplete: true) }
        let offset = keys.count
        keys.append(WarpTitle.normalized(windowTitle))
        if WarpTitle.matches(windowTitle: windowTitle, sessionTitle: target) {
            matchOffsets.append(offset)
        }
        if offset >= 3, keys[offset - 1] == keys[0], keys[offset] == keys[1] {
            let cycle = offset - 1
            cycleLength = cycle
            matchOffsets.removeAll { $0 >= cycle }
            return finish(isComplete: true)
        }
        guard nextPresses < limit else { return finish(isComplete: false) }
        nextPresses += 1
        return .next
    }

    /// Previous Tab switches that bring the window back to the tab it started on. Without a known
    /// cycle it's every switch made: an extra Previous in a one-tab window is harmless.
    public var pressesBackToStart: Int {
        guard let cycleLength else { return nextPresses }
        return nextPresses % cycleLength
    }

    public static func decide(_ windows: [TabSearch]) -> Decision {
        let matches = windows.enumerated().flatMap { index, search in search.matchOffsets.map { (index, $0) } }
        guard matches.count <= 1 else { return .duplicate }
        guard let (window, offset) = matches.first else { return .notFound }
        guard windows.allSatisfy(\.isComplete) else { return .incomplete }
        return .found(window: window, offset: offset)
    }

    private mutating func finish(isComplete: Bool) -> Step {
        self.isComplete = isComplete
        isDone = true
        return .done
    }
}
