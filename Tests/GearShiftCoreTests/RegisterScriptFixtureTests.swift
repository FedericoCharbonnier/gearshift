import Foundation
@testable import GearShiftCore

/// Cross-checks `skills/gearshift/register.sh`'s `printf` output against `SessionRecord`'s decoder, so the
/// script and the app can't silently drift. This literal is a real sample produced by running
/// register.sh (run under a fake `claude`) against a fixture whose cwd has a space, a double quote
/// and a backslash; only the temp directory prefix was shortened.
func runRegisterScriptFixtureTests() {
    suite("register.sh output decodes as SessionRecord") {
        let json = """
        {"sessionId":"9c858e35-1e1e-4c1a-9f1a-000000000001","cwd":"/tmp/gearshift-fixture/My Proj \\"quoted\\" \\\\ path","transcriptPath":"/tmp/gearshift-fixture/home/projects/-Users-alex-dev/9c858e35-1e1e-4c1a-9f1a-000000000001.jsonl","claudePid":60032,"registeredAt":"2026-09-30T16:50:29.561Z"}
        """
        let record = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        expectEqual(record.sessionId, "9c858e35-1e1e-4c1a-9f1a-000000000001")
        expectEqual(record.cwd, "/tmp/gearshift-fixture/My Proj \"quoted\" \\ path")
        expectEqual(
            record.transcriptPath,
            "/tmp/gearshift-fixture/home/projects/-Users-alex-dev/9c858e35-1e1e-4c1a-9f1a-000000000001.jsonl")
        expectEqual(record.claudePid, 60032)
        expectEqual(record.registeredAt, JSONLine.date("2026-09-30T16:50:29.561Z"))
        // Milliseconds survive re-encoding, so the newest registration stays the newest.
        let reencoded = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record))
        expectEqual(reencoded, record)
        expectEqual(record.nickname, nil)
    }

    suite("register.sh output with a nickname decodes as SessionRecord") {
        // `/gearshift my backend`, run the same way (temp directory prefix shortened).
        let json = """
        {"sessionId":"9c858e35-1e1e-4c1a-9f1a-000000000002","cwd":"/tmp/regfix/My Proj \\"quoted\\" \\\\ path","transcriptPath":"/tmp/regfix/home/projects/-x/9c858e35-1e1e-4c1a-9f1a-000000000002.jsonl","claudePid":84534,"registeredAt":"2026-09-30T17:18:22.386Z","nickname":"my backend"}
        """
        let record = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        expectEqual(record.nickname, "my backend")
        expectEqual(record.cwd, "/tmp/regfix/My Proj \"quoted\" \\ path")
        expectEqual(record.claudePid, 84534)
        expectEqual(try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record)), record)
    }

    suite("register.sh output with a terminal and tty decodes as SessionRecord") {
        // `/gearshift my backend` in Terminal: run under a fake `claude` on a pseudo-terminal of its
        // own (`script`), with TERM_PROGRAM=Apple_Terminal (temp directory prefix shortened).
        let json = """
        {"sessionId":"9c858e35-1e1e-4c1a-9f1a-000000000003","cwd":"/tmp/regfix2/My Proj \\"quoted\\" \\\\ path","transcriptPath":"/tmp/regfix2/home/projects/-x/9c858e35-1e1e-4c1a-9f1a-000000000003.jsonl","claudePid":973,"registeredAt":"2026-09-30T17:36:03.583Z","nickname":"my backend","terminal":"terminal","tty":"/dev/ttys003"}
        """
        let record = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        expectEqual(record.terminal, .terminal)
        expectEqual(record.tty, "/dev/ttys003")
        expectEqual(record.termProgram, nil)
        expectEqual(record.nickname, "my backend")
        expectEqual(record.cwd, "/tmp/regfix2/My Proj \"quoted\" \\ path")
        expectEqual(TerminalStrategy.location(of: record), .success(.tty(.terminal, "/dev/ttys003")))
        expectEqual(try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record)), record)
    }

    suite("register.sh output for another terminal decodes as SessionRecord") {
        // TERM_PROGRAM=vscode, no tty of its own (temp directory prefix shortened).
        let json = """
        {"sessionId":"9c858e35-1e1e-4c1a-9f1a-000000000004","cwd":"/tmp/regfix2/My Proj \\"quoted\\" \\\\ path","transcriptPath":"/tmp/regfix2/home/projects/-x/9c858e35-1e1e-4c1a-9f1a-000000000004.jsonl","claudePid":1007,"registeredAt":"2026-09-30T17:36:03.783Z","terminal":"other","termProgram":"vscode"}
        """
        let record = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        expectEqual(record.terminal, .other)
        expectEqual(record.tty, nil)
        expectEqual(record.termProgram, "vscode")
        expectEqual(TerminalStrategy.location(of: record), .failure(.unsupportedTerminal("vscode")))
        expectEqual(try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record)), record)
    }

    suite("a record from before terminals were recorded is Warp's") {
        let json = """
        {"sessionId":"9c858e35-1e1e-4c1a-9f1a-000000000001","cwd":"/x","transcriptPath":"/x/t.jsonl","claudePid":60032,"registeredAt":"2026-09-30T16:50:29.561Z"}
        """
        let record = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        expectEqual(record.terminal, nil)
        expectEqual(record.tty, nil)
        expectEqual(TerminalStrategy.location(of: record), .success(.warpTitle))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any] ?? [:]
        expect(object["terminal"] == nil && object["tty"] == nil && object["termProgram"] == nil, "nothing added when re-encoded")
    }

    suite("SessionRecord: terminal fields are validated") {
        func decode(_ extra: String) throws -> SessionRecord {
            let json = #"{"sessionId":"s","cwd":"/x","transcriptPath":"/t.jsonl","claudePid":7,"registeredAt":"2026-09-30T10:15:30Z"\#(extra)}"#
            return try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
        }
        expectEqual(try decode(#","terminal":"iterm","tty":"/dev/ttys012""#).tty, "/dev/ttys012")
        expectEqual(try decode(#","terminal":"iterm","tty":"/dev/ttys012\" then quit""#).tty, nil)
        expectEqual(try decode(#","terminal":"iterm","tty":"ttys012""#).tty, nil)
        expectEqual(try decode(#","terminal":"kitty""#).terminal, .other)
        expectEqual(try decode(#","terminal":"other","termProgram":"a b""#).termProgram, nil)
        expectEqual(try decode(#","terminal":"other","termProgram":"WezTerm""#).termProgram, "WezTerm")
        expectEqual(try decode(#","terminal":"other","termProgram":"caf\u00e9""#).termProgram, nil)
        expect((try? decode(#","terminal":7"#)) == nil, "a terminal that isn't a string fails")
    }
}
