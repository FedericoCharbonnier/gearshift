import Foundation
@testable import GearShiftCore

func runGearConfigTests() {
    suite("GearConfig: defaults") {
        let gears = GearConfig.defaults.gears
        expectEqual(Set(gears.keys), Set(Gear.allCases))
        func expectGear(_ gear: Gear, _ label: String, _ displayName: String, _ model: String, _ effort: Effort?) {
            expectEqual(gears[gear], GearSetting(label: label, displayName: displayName, model: model, effort: effort))
        }
        expectGear(.reverse, "Haiku", "HAIKU 4.5", "haiku", nil)
        expectGear(.neutral, "Default", "DEFAULT", "default", nil)
        expectGear(.one, "Sonnet · med", "SONNET 5 · MED", "sonnet", .medium)
        expectGear(.two, "Sonnet · high", "SONNET 5 · HIGH", "sonnet", .high)
        expectGear(.three, "Opus · med", "OPUS 5.5 · MED", "opus", .medium)
        expectGear(.four, "Opus · max", "OPUS 5.5 · MAX", "opus", .max)
        expectGear(.five, "Fable", "FABLE 5.1", "fable", nil)
        expectEqual(GearConfig.defaults.isMuted, false)
        expectEqual(GearConfig.defaults.keepsOnTop, true)
        expectEqual(GearConfig.defaults.returnsToPreviousApp, true)
        expectEqual(Effort.allCases.map(\.rawValue), ["low", "medium", "high", "xhigh", "max"])

        var partial = GearConfig.defaults
        partial.gears[.three] = nil
        partial.gears[.neutral] = nil
        expectEqual(partial.fillingMissingGears(), GearConfig.defaults)
    }

    suite("GearConfig: round trip") {
        var config = GearConfig.defaults
        config.isMuted = true
        config.keepsOnTop = false
        config.returnsToPreviousApp = false
        config.gears[.neutral] = GearSetting(label: "Mine", displayName: "MINE", model: "opus[1m]", effort: .xhigh)
        config.gears[.two]?.effort = nil
        let decoded = try JSONDecoder().decode(GearConfig.self, from: JSONEncoder().encode(config))
        expectEqual(decoded, config)
    }

    suite("GearConfig: a v1 file loads") {
        let v1 = #"""
        {"gears":{
          "1":{"label":"Haiku","displayName":"HAIKU 4.5","agent":"claude","model":"haiku"},
          "5":{"label":"GPT-5.5","displayName":"GPT-5.5","agent":"codex","model":"gpt-5.5"},
          "R":{"label":"Default","displayName":"DEFAULT","agent":"claude","model":""}},
         "recentProjects":["/x"],"sessionIDs":{"/x":{"1":"abc"}},"isMuted":true}
        """#
        let config = try JSONDecoder().decode(GearConfig.self, from: Data(v1.utf8)).fillingMissingGears()
        expectEqual(config.isMuted, true)
        expectEqual(config.keepsOnTop, true)  // files from before the setting existed float
        expectEqual(config.returnsToPreviousApp, true)  // and go back to where the user was
        expectEqual(Set(config.gears.keys), Set(Gear.allCases))
        // v1 gears held one agent + model on a different layout; they give way to the v2 table.
        expectEqual(config.gears, GearConfig.defaults.gears)
    }

    suite("GearConfig: a bad gear falls back to its default") {
        let json = #"""
        {"gears":{
          "3":{"label":"Opus · turbo","displayName":"OPUS TURBO","model":"opus","effort":"turbo"},
          "4":{"label":"Big","displayName":"BIG","model":"opus","effort":"xhigh"},
          "2":"sonnet"},
         "isMuted":false}
        """#
        let config = try JSONDecoder().decode(GearConfig.self, from: Data(json.utf8)).fillingMissingGears()
        expectEqual(config.gears[.three], GearConfig.defaults.gears[.three])
        expectEqual(config.gears[.two], GearConfig.defaults.gears[.two])
        expectEqual(config.gears[.four], GearSetting(label: "Big", displayName: "BIG", model: "opus", effort: .xhigh))

        let notAnObject = try JSONDecoder().decode(GearConfig.self, from: Data(#"{"gears":[1,2],"isMuted":true}"#.utf8))
        expectEqual(notAnObject.fillingMissingGears().gears, GearConfig.defaults.gears)
        expectEqual(notAnObject.isMuted, true)
    }

    suite("GearConfig: returnsToPreviousApp decodes on its own") {
        let off = try JSONDecoder().decode(GearConfig.self, from: Data(#"{"isMuted":true,"keepsOnTop":false,"returnsToPreviousApp":false}"#.utf8))
        expectEqual(off.returnsToPreviousApp, false)
        expectEqual(off.keepsOnTop, false)
        // A value of the wrong type falls back to the default without costing the other fields.
        let bad = try JSONDecoder().decode(GearConfig.self, from: Data(#"{"isMuted":true,"keepsOnTop":false,"returnsToPreviousApp":"no"}"#.utf8))
        expectEqual(bad.returnsToPreviousApp, true)
        expectEqual(bad.isMuted, true)
        expectEqual(bad.keepsOnTop, false)
        let missing = try JSONDecoder().decode(GearConfig.self, from: Data("{}".utf8))
        expectEqual(missing.returnsToPreviousApp, true)
        // Written under its own key.
        var config = GearConfig.defaults
        config.returnsToPreviousApp = false
        let json = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        expect(json.contains(#""returnsToPreviousApp":false"#), "encoded")
    }
}
