import Foundation

/// Helpers for reading JSONL transcript lines.
enum JSONLine {
    static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter = ISO8601DateFormatter()

    static func date(_ string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? wholeSecondFormatter.date(from: string)
    }
}
