import Foundation

/// Finds the transcript's record of a slash command typed into the session, which shows that it
/// reached Claude Code and ran. Claude Code 2.1.282 writes it as
/// `{"type":"system","subtype":"local_command","content":"<command-name>/model</command-name>\n
/// <command-message>model</command-message>\n <command-args>opus</command-args>"}` followed by a
/// `<local-command-stdout>` line; older versions wrote the same string as a user message's content.
public enum CommandConfirmation {
    public enum Outcome: Equatable {
        case confirmed
        /// The command ran without its arguments (e.g. only `/model` arrived and opened the picker).
        case emptyArgs
        case notFound
    }

    /// `command` includes the slash, e.g. `/model`.
    public static func find(command: String, args: String, inLines lines: [String]) -> Outcome {
        let nameTag = "<command-name>\(command)</command-name>"
        let expectedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        var outcome = Outcome.notFound
        for line in lines where line.contains(nameTag) {
            guard let content = recordContent(line), content.contains(nameTag) else { continue }
            let recordedArgs = argsTag(in: content)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if recordedArgs == expectedArgs {
                return .confirmed
            }
            if recordedArgs.isEmpty {
                outcome = .emptyArgs
            }
        }
        return outcome
    }

    /// The record string of a command line, or nil when the line isn't one.
    private static func recordContent(_ line: String) -> String? {
        guard let object = JSONLine.object(line), object["isSidechain"] as? Bool != true else { return nil }
        switch object["type"] as? String {
        case "system" where object["subtype"] as? String == "local_command":
            return object["content"] as? String
        case "user":
            return (object["message"] as? [String: Any])?["content"] as? String
        default:
            return nil
        }
    }

    private static func argsTag(in content: String) -> String? {
        guard let open = content.range(of: "<command-args>"),
              let close = content.range(of: "</command-args>", range: open.upperBound..<content.endIndex)
        else { return nil }
        return String(content[open.upperBound..<close.lowerBound])
    }
}
