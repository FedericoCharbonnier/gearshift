@testable import GearShiftCore

func runGearTests() {
    suite("Gear") {
        expectEqual(Gear.drivable.map(\.rawValue), ["1", "2", "3", "4", "5", "R"])
        expectEqual(Gear.at(column: 0, row: 0), .one)
        expectEqual(Gear.at(column: 1, row: 1), .four)
        expectEqual(Gear.at(column: 2, row: 1), .reverse)
        expect(Gear.neutral.slot == nil, "neutral has no slot")
        for gear in Gear.drivable {
            guard let slot = gear.slot else {
                expect(false, "\(gear) has no slot")
                continue
            }
            expectEqual(Gear.at(column: slot.column, row: slot.row), gear)
        }
        expectEqual(Set(Gear.drivable.compactMap { $0.slot.map { "\($0.column),\($0.row)" } }).count, Gear.drivable.count)
        expectEqual(Gear.five.colorHex, "#8fd8cf")
        expectEqual(Gear.five.shiftKick, 6900)
    }
}
