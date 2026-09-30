@testable import GearShiftCore

func runTurboPasswordsTests() {
    suite("TurboPasswords") {
        let passwords = TurboPasswords(fileContents: "alpha\n  Beta  \n\n\r\nalpha\n")
        expect(passwords != nil, "a file with passwords loads")
        expect(passwords?.accepts("alpha") == true, "an exact line")
        expect(passwords?.accepts(" Beta ") == true, "surrounding spaces don't count")
        expect(passwords?.accepts("beta") == false, "case-sensitive: list each accepted spelling")
        expect(passwords?.accepts("") == false, "empty never unlocks")
        expect(passwords?.accepts("alph") == false, "no prefixes")
        expect(TurboPasswords(fileContents: "\n  \n") == nil, "a file without passwords turns the button off")
    }
}
