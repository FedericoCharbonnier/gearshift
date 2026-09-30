@testable import GearShiftCore

func runCommandConfirmationTests() {
    suite("CommandConfirmation: current system-line shape") {
        let lines = [Fixture.systemCommand("model", args: "opus"), Fixture.systemStdout("Set model to `Opus 5.5`")]
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: lines), .confirmed)
        expectEqual(CommandConfirmation.find(command: "/model", args: "sonnet", inLines: lines), .notFound)
        expectEqual(CommandConfirmation.find(command: "/effort", args: "opus", inLines: lines), .notFound)
        expectEqual(
            CommandConfirmation.find(command: "/model", args: "opus[1m]", inLines: [Fixture.systemCommand("model", args: "opus[1m]")]),
            .confirmed)
        expectEqual(
            CommandConfirmation.find(command: "/effort", args: "auto", inLines: [Fixture.attachment, Fixture.systemCommand("effort", args: "auto")]),
            .confirmed)
    }

    suite("CommandConfirmation: older user-message shape") {
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: [Fixture.userCommand("model", args: "opus")]), .confirmed)
    }

    suite("CommandConfirmation: empty args when args were typed is a failure") {
        let empty = [Fixture.systemCommand("model", args: "")]
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: empty), .emptyArgs)
        // A later record with the args still confirms.
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: empty + [Fixture.systemCommand("model", args: "opus")]), .confirmed)
    }

    suite("CommandConfirmation: only real command records count") {
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: []), .notFound)
        // Someone pasting the tags in a prompt (array content), or Claude quoting them.
        let pasted = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<command-name>/model</command-name><command-args>opus</command-args>"}]}}"#
        let quoted = #"{"type":"assistant","message":{"id":"m","role":"assistant","content":"<command-name>/model</command-name><command-args>opus</command-args>"}}"#
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: [pasted, quoted]), .notFound)
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: [Fixture.systemCommand("model", args: "opus", sidechain: true)]), .notFound)
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: [Fixture.systemCommand("models", args: "opus")]), .notFound)
        expectEqual(CommandConfirmation.find(command: "/model", args: "opus", inLines: ["garbage", Fixture.systemStdout("Set model")]), .notFound)
    }
}
