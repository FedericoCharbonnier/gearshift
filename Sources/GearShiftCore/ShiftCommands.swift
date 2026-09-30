import Foundation

/// One slash command typed into the session, e.g. `/model opus`.
public struct ShiftCommand: Equatable {
    /// With the slash, e.g. `/model`.
    public let name: String
    public let args: String

    public init(name: String, args: String) {
        self.name = name
        self.args = args
    }

    public var line: String { "\(name) \(args)" }
}

/// The slash commands typed into a Claude Code session to put it in a gear. Effort is always sent,
/// as `auto` when the gear has none, so that it doesn't carry over from the previous gear.
public enum ShiftCommands {
    /// A model alias or id: no spaces, newlines or shell/terminal metacharacters, so the typed line
    /// can't turn into something else.
    private static let modelPattern = try! NSRegularExpression(pattern: #"\A[A-Za-z0-9][A-Za-z0-9._:\[\]-]*\z"#)

    public static func isValidModel(_ model: String) -> Bool {
        let range = NSRange(model.startIndex..., in: model)
        return modelPattern.firstMatch(in: model, range: range) != nil
    }

    /// Nil when the model isn't valid: nothing should be typed then.
    public static func commands(for setting: GearSetting) -> [ShiftCommand]? {
        guard isValidModel(setting.model) else { return nil }
        return [
            ShiftCommand(name: "/model", args: setting.model),
            ShiftCommand(name: "/effort", args: setting.effort?.rawValue ?? "auto"),
        ]
    }
}
