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

    suite("TurboPasswords: built-in, stored as SHA-256") {
        let builtIn = TurboPasswords.builtIn
        expect(builtIn.accepts("OYM"), "upper case")
        expect(builtIn.accepts("oym"), "lower case")
        expect(builtIn.accepts(" oym "), "surrounding spaces don't count")
        expect(!builtIn.accepts("Oym"), "other spellings don't")
        expect(!builtIn.accepts(""), "empty never unlocks")
        expect(!builtIn.accepts("c764211e2c4ad08fc1ab801f5e657b35f544bd92e65fa931a99e5b5b09345d36"), "the hash itself isn't a password")
    }
}
