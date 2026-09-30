import Foundation
import GearShiftCore

/// The live sessions and what their transcripts say at one poll.
struct SessionSnapshot {
    var sessions: [SessionRecord]
    /// Session id → title, last prompt, model and branch from the transcript.
    var infos: [String: SessionInfo]

    /// Session id → title from the transcript; missing when it has none (yet). The only thing a
    /// shift looks for in Warp.
    var titles: [String: String] {
        infos.compactMapValues(\.title)
    }
}

/// Reads the registry and the session transcripts. Confined to one serial queue: pruning the
/// registry and reading transcripts touch the disk.
final class SessionPoller {
    private let registry: SessionRegistry
    private var infoCache = SessionInfoCache()

    init(registry: SessionRegistry) {
        self.registry = registry
    }

    func poll() -> SessionSnapshot {
        let sessions = registry.liveSessions()
        infoCache.retain(transcripts: Set(sessions.map(\.transcriptPath)))
        return SessionSnapshot(sessions: sessions, infos: infos(of: sessions))
    }

    private func infos(of sessions: [SessionRecord]) -> [String: SessionInfo] {
        var infos: [String: SessionInfo] = [:]
        for session in sessions {
            infos[session.sessionId] = infoCache.info(transcriptPath: session.transcriptPath)
        }
        return infos
    }
}

/// Session infos by transcript path. Each transcript is read in full once, then only what was
/// appended (a `/rename` early on still wins over later ai-titles).
struct SessionInfoCache {
    private var trackers: [String: SessionInfoTracker] = [:]

    mutating func info(transcriptPath path: String) -> SessionInfo {
        let tracker = trackers[path] ?? SessionInfoTracker(url: URL(fileURLWithPath: path))
        trackers[path] = tracker
        return tracker.current()
    }

    /// Forgets transcripts of sessions that are gone.
    mutating func retain(transcripts: Set<String>) {
        trackers = trackers.filter { transcripts.contains($0.key) }
    }
}
