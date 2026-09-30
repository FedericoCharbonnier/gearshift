import Foundation

/// The connected sessions, one `<sessionId>.json` file each in `directory`.
public struct SessionRegistry {
    public let directory: URL

    public init(directory: URL = SessionRegistry.defaultDirectory) {
        self.directory = directory
    }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GearShift/sessions", isDirectory: true)
    }

    public func register(_ record: SessionRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: fileURL(for: record.sessionId), options: .atomic)
    }

    /// Sessions whose `claude` process is still running, newest registration first. Files of
    /// sessions that ended, and files that don't decode, are deleted, unless `register.sh` rewrote
    /// them meanwhile. Only `*.json` files are read, so a temp file being written next to them is
    /// left alone.
    public func liveSessions(isAlive: (Int32) -> Bool = SessionRegistry.isProcessAlive) -> [SessionRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var sessions: [SessionRecord] = []
        for file in files where file.pathExtension == "json" {
            guard let snapshot = try? FileSnapshot(of: file) else { continue }
            guard let record = try? JSONDecoder().decode(SessionRecord.self, from: snapshot.data),
                  isAlive(record.claudePid)
            else {
                removeIfUnchanged(file, since: snapshot)
                continue
            }
            sessions.append(record)
        }
        return sessions.sorted {
            ($0.registeredAt, $0.sessionId) > ($1.registeredAt, $1.sessionId)
        }
    }

    /// A file's content and modification date when it was read.
    struct FileSnapshot {
        let data: Data
        let modified: Date?

        init(of file: URL) throws {
            // The date first: a write after it changes the date, one before it shows in the data.
            modified = Self.modificationDate(of: file)
            data = try Data(contentsOf: file)
        }

        static func modificationDate(of file: URL) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        }
    }

    /// Deletes a stale file only if it still is what was read: a `/gearshift` that re-registered the
    /// session in between must not be lost.
    func removeIfUnchanged(_ file: URL, since snapshot: FileSnapshot) {
        guard FileSnapshot.modificationDate(of: file) == snapshot.modified,
              (try? Data(contentsOf: file)) == snapshot.data
        else { return }
        try? FileManager.default.removeItem(at: file)
    }

    public func remove(sessionId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: sessionId))
    }

    /// `kill(pid, 0)` probes without sending a signal. A pid of 0 or less would address a process
    /// group (or every process) and always look alive, so it never counts.
    public static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private func fileURL(for sessionId: String) -> URL {
        directory.appendingPathComponent("\(sessionId).json")
    }
}
