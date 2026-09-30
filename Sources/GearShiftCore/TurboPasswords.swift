import CryptoKit
import Foundation

/// The accepted passwords for the TURBO easter egg. The built-in ones are kept as SHA-256 hashes so
/// the source doesn't spell them out; a local `passwords` file (one per line, plain text) replaces
/// them. Case-sensitive, so each accepted spelling is listed on its own.
public struct TurboPasswords: Equatable {
    private let acceptedHashes: Set<String>

    /// SHA-256 of "OYM" and "oym".
    public static let builtIn = TurboPasswords(hashes: [
        "c764211e2c4ad08fc1ab801f5e657b35f544bd92e65fa931a99e5b5b09345d36",
        "3419f05c1608c32ff41cc16151692c3dff9526f4bcb20349816d94d47f8595fa",
    ])

    private init(hashes: Set<String>) {
        acceptedHashes = hashes
    }

    /// nil when the file lists no passwords.
    public init?(fileContents: String) {
        let lines = fileContents
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }
        acceptedHashes = Set(lines.map(Self.hash))
    }

    public func accepts(_ attempt: String) -> Bool {
        let attempt = attempt.trimmingCharacters(in: .whitespaces)
        return !attempt.isEmpty && acceptedHashes.contains(Self.hash(attempt))
    }

    private static func hash(_ password: String) -> String {
        SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
