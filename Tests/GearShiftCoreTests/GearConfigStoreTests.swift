import Foundation
@testable import GearShiftCore

func runGearConfigStoreTests() {
    suite("GearConfigStore") {
        let directory = makeTemporaryDirectory()
        let store = GearConfigStore(url: directory.appendingPathComponent("nested/config.json"))
        expectEqual(store.load(), GearConfig.defaults)

        var config = GearConfig.defaults
        config.gears[.four]?.effort = .xhigh
        config.isMuted = true
        try store.save(config)
        expectEqual(store.load(), config)

        let json = try String(contentsOf: store.url, encoding: .utf8)
        expect(json.contains("\"R\" : {"), "gears are stored as a JSON object keyed by gear")
        expect(json.contains("\"N\" : {"), "neutral is stored too")

        try "not json".write(to: store.url, atomically: true, encoding: .utf8)
        expectEqual(store.load(), GearConfig.defaults)
    }

    suite("GearConfigStore: tolerates schema drift") {
        let store = GearConfigStore(url: makeTemporaryDirectory().appendingPathComponent("config.json"))
        let opus = #"{"label":"Big","displayName":"BIG","model":"opus","effort":"max"}"#

        // Missing isMuted: the stored gears survive and missing gears are filled in.
        try #"{"gears":{"4":\#(opus)}}"#.write(to: store.url, atomically: true, encoding: .utf8)
        var loaded = store.load()
        expectEqual(loaded.isMuted, false)
        expectEqual(loaded.gears[.four]?.label, "Big")
        expectEqual(loaded.gears[.one], GearConfig.defaults.gears[.one])

        // Unknown gear keys and unknown top-level keys are ignored; the rest loads.
        try #"{"gears":{"X":\#(opus),"N":\#(opus)},"recentProjects":["/p/b"],"future":1,"isMuted":true}"#
            .write(to: store.url, atomically: true, encoding: .utf8)
        loaded = store.load()
        expectEqual(Set(loaded.gears.keys), Set(Gear.allCases))
        expectEqual(loaded.gears[.neutral]?.label, "Big")
        expectEqual(loaded.isMuted, true)

        try "{}".write(to: store.url, atomically: true, encoding: .utf8)
        expectEqual(store.load(), GearConfig.defaults)
    }
}
