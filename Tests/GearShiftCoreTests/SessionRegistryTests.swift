import Foundation
@testable import GearShiftCore

func sessionRecord(_ id: String, pid: Int32 = 100, registeredAt: String = "2026-09-30T10:00:00Z") -> SessionRecord {
    SessionRecord(
        sessionId: id,
        cwd: "/Users/me/dev/\(id)",
        transcriptPath: "/Users/me/.claude/projects/-Users-me-dev-\(id)/\(id).jsonl",
        claudePid: pid,
        registeredAt: JSONLine.date(registeredAt)!
    )
}

func runSessionRegistryTests() {
    suite("SessionRecord: JSON shape") {
        let record = sessionRecord("a", pid: 4242, registeredAt: "2026-09-30T10:15:30Z")
        let data = try JSONEncoder().encode(record)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        expectEqual(Set(object.keys), ["sessionId", "cwd", "transcriptPath", "claudePid", "registeredAt"])
        expectEqual(object["registeredAt"] as? String, "2026-09-30T10:15:30Z")
        expectEqual(object["claudePid"] as? Int, 4242)
        expectEqual(try JSONDecoder().decode(SessionRecord.self, from: data), record)

        // The format register.sh writes: whole-second UTC; fractional seconds are accepted too.
        let written = #"{"sessionId":"s","cwd":"/x","transcriptPath":"/t.jsonl","claudePid":7,"registeredAt":"2026-09-30T10:15:30.250Z"}"#
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: Data(written.utf8))
        expectEqual(decoded.registeredAt, JSONLine.date("2026-09-30T10:15:30.250Z"))
        let badDate = #"{"sessionId":"s","cwd":"/x","transcriptPath":"/t.jsonl","claudePid":7,"registeredAt":"yesterday"}"#
        expect((try? JSONDecoder().decode(SessionRecord.self, from: Data(badDate.utf8))) == nil, "a bad date fails")
    }

    suite("SessionRecord: optional nickname") {
        // Absent: decodes as nil and isn't written back.
        let plain = sessionRecord("a")
        expectEqual(plain.nickname, nil)
        let plainObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any] ?? [:]
        expect(plainObject["nickname"] == nil, "no nickname key when nil")

        let written = #"{"sessionId":"s","cwd":"/x","transcriptPath":"/t.jsonl","claudePid":7,"registeredAt":"2026-09-30T10:15:30.250Z","nickname":"my backend"}"#
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: Data(written.utf8))
        expectEqual(decoded.nickname, "my backend")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any] ?? [:]
        expectEqual(object["nickname"] as? String, "my backend")
        expectEqual(try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(decoded)), decoded)

        // Blank counts as none.
        let blank = #"{"sessionId":"s","cwd":"/x","transcriptPath":"/t.jsonl","claudePid":7,"registeredAt":"2026-09-30T10:15:30Z","nickname":"  "}"#
        expectEqual(try JSONDecoder().decode(SessionRecord.self, from: Data(blank.utf8)).nickname, nil)
        let null = #"{"sessionId":"s","cwd":"/x","transcriptPath":"/t.jsonl","claudePid":7,"registeredAt":"2026-09-30T10:15:30Z","nickname":null}"#
        expectEqual(try JSONDecoder().decode(SessionRecord.self, from: Data(null.utf8)).nickname, nil)
    }

    suite("SessionRegistry: register and list, newest first") {
        let directory = makeTemporaryDirectory().appendingPathComponent("nested/sessions", isDirectory: true)
        let registry = SessionRegistry(directory: directory)
        expectEqual(registry.liveSessions(isAlive: { _ in true }), [])  // directory doesn't exist yet

        let older = sessionRecord("older", registeredAt: "2026-09-30T09:00:00Z")
        let newer = sessionRecord("newer", registeredAt: "2026-09-30T11:00:00Z")
        try registry.register(older)
        try registry.register(newer)
        expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("older.json").path), "file per session")
        expectEqual(registry.liveSessions(isAlive: { _ in true }), [newer, older])

        // Registering again replaces the record.
        let again = sessionRecord("older", registeredAt: "2026-09-30T12:00:00Z")
        try registry.register(again)
        expectEqual(registry.liveSessions(isAlive: { _ in true }), [again, newer])
    }

    suite("SessionRegistry: prunes dead and corrupt sessions") {
        let directory = makeTemporaryDirectory()
        let registry = SessionRegistry(directory: directory)
        let alive = sessionRecord("alive", pid: 1)
        try registry.register(alive)
        try registry.register(sessionRecord("dead", pid: 2))
        try "{not json".write(to: directory.appendingPathComponent("corrupt.json"), atomically: true, encoding: .utf8)
        // Not a session file (e.g. register.sh's temp file mid-write): ignored and kept.
        try "{}".write(to: directory.appendingPathComponent("x.json.tmp"), atomically: true, encoding: .utf8)

        expectEqual(registry.liveSessions(isAlive: { $0 == 1 }), [alive])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        expectEqual(remaining, ["alive.json", "x.json.tmp"])
    }

    suite("SessionRecord: sub-second registration times survive a round trip") {
        let precise = sessionRecord("p", registeredAt: "2026-09-30T10:15:30.250Z")
        let data = try JSONEncoder().encode(precise)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        expectEqual(object["registeredAt"] as? String, "2026-09-30T10:15:30.250Z")
        expectEqual(try JSONDecoder().decode(SessionRecord.self, from: data), precise)
    }

    suite("SessionRegistry: a file rewritten since it was read is not pruned") {
        let directory = makeTemporaryDirectory()
        let registry = SessionRegistry(directory: directory)
        let file = directory.appendingPathComponent("s.json")
        try "{not json".write(to: file, atomically: true, encoding: .utf8)
        let snapshot = try SessionRegistry.FileSnapshot(of: file)
        // register.sh replaces the file between the read and the delete.
        try registry.register(sessionRecord("s", pid: 7))
        registry.removeIfUnchanged(file, since: snapshot)
        expect(FileManager.default.fileExists(atPath: file.path), "the fresh registration survives")
        expectEqual(registry.liveSessions(isAlive: { $0 == 7 }).map(\.sessionId), ["s"])

        // Unchanged: removed.
        let unchanged = try SessionRegistry.FileSnapshot(of: file)
        registry.removeIfUnchanged(file, since: unchanged)
        expect(!FileManager.default.fileExists(atPath: file.path), "an unchanged file is removed")
    }

    suite("SessionRegistry: remove") {
        let registry = SessionRegistry(directory: makeTemporaryDirectory())
        try registry.register(sessionRecord("a"))
        try registry.register(sessionRecord("b"))
        registry.remove(sessionId: "a")
        registry.remove(sessionId: "missing")
        expectEqual(registry.liveSessions(isAlive: { _ in true }).map(\.sessionId), ["b"])
    }

    suite("SessionRegistry: process liveness") {
        expect(SessionRegistry.isProcessAlive(getpid()), "this process is alive")
        expect(!SessionRegistry.isProcessAlive(0), "pid 0 would signal the whole process group")
        expect(!SessionRegistry.isProcessAlive(-1), "negative pids are never sessions")
        expect(!SessionRegistry.isProcessAlive(Int32.max), "no such process")
    }
}
