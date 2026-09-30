import Foundation

/// The accepted passwords for the local TURBO easter egg: one per line of a file the user keeps
/// outside the repo. Case-sensitive, so each accepted spelling gets its own line.
public struct TurboPasswords: Equatable {
    private let accepted: Set<String>

    /// nil when the file lists no passwords, which turns the button off.
    public init?(fileContents: String) {
        let lines = fileContents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        accepted = Set(lines)
    }

    public func accepts(_ attempt: String) -> Bool {
        let attempt = attempt.trimmingCharacters(in: .whitespaces)
        return !attempt.isEmpty && accepted.contains(attempt)
    }
}
