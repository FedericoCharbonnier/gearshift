@testable import GearShiftCore

func runShiftCommandsTests() {
    func lines(_ setting: GearSetting) -> [String]? {
        ShiftCommands.commands(for: setting)?.map(\.line)
    }

    suite("ShiftCommands") {
        let opusMax = GearSetting(label: "Opus · max", displayName: "OPUS 5.5 · MAX", model: "opus", effort: .max)
        expectEqual(lines(opusMax), ["/model opus", "/effort max"])
        expectEqual(ShiftCommands.commands(for: opusMax)?.first, ShiftCommand(name: "/model", args: "opus"))
        let xhigh = GearSetting(label: "x", displayName: "X", model: "opus[1m]", effort: .xhigh)
        expectEqual(lines(xhigh), ["/model opus[1m]", "/effort xhigh"])

        expectEqual(lines(GearConfig.defaults.gears[.neutral]!), ["/model default", "/effort auto"])
        expectEqual(lines(GearConfig.defaults.gears[.reverse]!), ["/model haiku", "/effort auto"])
    }

    suite("ShiftCommands: every default gear is valid") {
        for (gear, setting) in GearConfig.defaults.gears {
            expect(ShiftCommands.commands(for: setting) != nil, "gear \(gear.rawValue)")
        }
    }

    suite("ShiftCommands: model validation") {
        for valid in ["sonnet", "opus[1m]", "claude-opus-5-5", "claude-sonnet-5@20260101".replacingOccurrences(of: "@", with: "."), "us.anthropic.claude:0", "A", "9x"] {
            expect(ShiftCommands.isValidModel(valid), "\(valid) is valid")
        }
        for invalid in ["", " ", " sonnet", "sonnet ", "son net", "-opus", ".opus", "[1m]", "opus\n", "opus;rm", "opus/x", "opus\u{7F}", "ópus", "opus`", "opus$x", "opus\"", "opus\t"] {
            expect(!ShiftCommands.isValidModel(invalid), "\(invalid.debugDescription) is invalid")
        }
        let bad = GearSetting(label: "x", displayName: "X", model: "sonnet\n/effort max")
        expect(ShiftCommands.commands(for: bad) == nil, "an invalid model yields no commands")
        let empty = GearSetting(label: "x", displayName: "X", model: "")
        expect(ShiftCommands.commands(for: empty) == nil, "an empty model yields no commands")
    }
}
