import Foundation

/// Short, lowercase model names for display: `claude-opus-5-5` → `opus 5.5`.
public enum ModelName {
    /// Model ids (`claude-haiku-4-5-20251001` → `haiku 4.5`, a `[1m]` suffix → ` 1M`), names `/model`
    /// printed (`Opus 5.5 (1M context)` → `opus 5.5 1M`), and anything else as it is.
    public static func display(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = trimmed
        var suffix = ""
        if base.lowercased().hasSuffix("[1m]") {
            base = String(base.dropLast(4))
            suffix = " 1M"
        }
        if let name = fromId(base) ?? fromDisplayName(base) {
            return name + suffix
        }
        return trimmed
    }

    /// The model named in `/model`'s output, e.g. `Opus 5.5 (1M context)` from
    /// ``<local-command-stdout>Set model to `Opus 5.5 (1M context)` and saved as your default…``
    /// (older versions bold the name with ANSI codes and follow it with ` with <effort> effort`).
    public static func switched(commandOutput content: String) -> String? {
        guard let open = content.range(of: "<local-command-stdout>"),
              let close = content.range(of: "</local-command-stdout>", range: open.upperBound..<content.endIndex)
        else { return nil }
        let text = String(content[open.upperBound..<close.lowerBound])
            .replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Set model to "
        guard text.hasPrefix(prefix) else { return nil }
        var rest = Substring(text.dropFirst(prefix.count))
        var name: Substring
        if rest.hasPrefix("`") {
            rest = rest.dropFirst()
            name = rest.prefix { $0 != "`" }
        } else {
            name = rest
            for separator in [" with ", " and saved"] {
                if let range = name.range(of: separator) {
                    name = name[..<range.lowerBound]
                }
            }
        }
        let result = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return result.isEmpty ? nil : result
    }

    /// `claude-<family>-<major>[-<minor>][-<date>]`, or the older `claude-<major>[-<minor>]-<family>…`.
    private static func fromId(_ id: String) -> String? {
        for (pattern, family, major, minor) in idPatterns {
            guard let match = id.firstMatch(of: pattern) else { continue }
            let parts = match.output
            let version = [parts[major].substring, parts[minor].substring].compactMap { $0 }.joined(separator: ".")
            guard let familyName = parts[family].substring else { continue }
            return "\(familyName) \(version)"
        }
        return nil
    }

    // Swift 5.10 without RegexBuilder: runtime regexes with numbered capture groups.
    private static let idPatterns: [(Regex<AnyRegexOutput>, Int, Int, Int)] = [
        (try! Regex(#"^claude-([a-z]+)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?$"#), 1, 2, 3),
        (try! Regex(#"^claude-(\d+)(?:-(\d{1,2}))?-([a-z]+)(?:-\d{8})?$"#), 3, 1, 2),
    ]

    /// `Opus 5 (1M context) (default)` → `opus 5 1M`: lowercase, `(1M …)` becomes ` 1M`, other
    /// parentheses go. Only for names with a capital, a space or a parenthesis; ids stay as they are.
    private static func fromDisplayName(_ name: String) -> String? {
        guard name.contains(where: { $0.isUppercase || $0 == " " || $0 == "(" }) else { return nil }
        var isLongContext = false
        let withoutParentheses = name.replacing(try! Regex(#"\(([^)]*)\)"#)) { match in
            if let inner = match.output[1].substring, inner.lowercased().contains("1m") {
                isLongContext = true
            }
            return " "
        }
        let words = withoutParentheses.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !words.isEmpty else { return nil }
        return words + (isLongContext ? " 1M" : "")
    }
}
