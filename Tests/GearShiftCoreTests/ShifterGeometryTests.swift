import CoreGraphics
@testable import GearShiftCore

func runShifterGeometryTests() {
    suite("ShifterGeometry") {
        expectEqual(ShifterGeometry.restPosition(for: .neutral), CGPoint(x: 118, y: 118))
        expectEqual(ShifterGeometry.restPosition(for: .one), CGPoint(x: 52, y: 52))
        expectEqual(ShifterGeometry.restPosition(for: .four), CGPoint(x: 118, y: 184))
        expectEqual(ShifterGeometry.restPosition(for: .reverse), CGPoint(x: 184, y: 184))

        // Slides along the rail when not lined up with a slot.
        expectEqual(ShifterGeometry.constrain(CGPoint(x: 80, y: 120), from: CGPoint(x: 118, y: 118)), CGPoint(x: 80, y: 118))
        // Drops into a slot when lined up and pulled far enough off the rail.
        expectEqual(ShifterGeometry.constrain(CGPoint(x: 55, y: 90), from: CGPoint(x: 60, y: 118)), CGPoint(x: 52, y: 90))
        // Inside a slot it can only move vertically.
        expectEqual(ShifterGeometry.constrain(CGPoint(x: 100, y: 70), from: CGPoint(x: 52, y: 90)), CGPoint(x: 52, y: 70))
        // Back near the rail it slides sideways again.
        expectEqual(ShifterGeometry.constrain(CGPoint(x: 100, y: 110), from: CGPoint(x: 52, y: 90)), CGPoint(x: 100, y: 118))
        // Clamped to the slot ends.
        expectEqual(ShifterGeometry.constrain(CGPoint(x: 52, y: 0), from: CGPoint(x: 52, y: 90)), CGPoint(x: 52, y: 52))

        expectEqual(ShifterGeometry.gear(atRelease: CGPoint(x: 52, y: 60)), .one)
        expectEqual(ShifterGeometry.gear(atRelease: CGPoint(x: 118, y: 80)), .three)
        expectEqual(ShifterGeometry.gear(atRelease: CGPoint(x: 118, y: 150)), .four)
        expectEqual(ShifterGeometry.gear(atRelease: CGPoint(x: 184, y: 180)), .reverse)
        expectEqual(ShifterGeometry.gear(atRelease: CGPoint(x: 118, y: 100)), .neutral)
    }
}
