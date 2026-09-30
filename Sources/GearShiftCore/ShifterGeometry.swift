import CoreGraphics

/// Geometry of the H-pattern gate in a `size`×`size` square. The knob's centre moves along the
/// rail (y = `rail`) and three vertical slots (x = `columns`).
public enum ShifterGeometry {
    public static let size: CGFloat = 236
    public static let columns: [CGFloat] = [52, 118, 184]
    public static let rail: CGFloat = 118
    public static let top: CGFloat = 52
    public static let bottom: CGFloat = 184
    static let railTolerance: CGFloat = 18
    static let gateTolerance: CGFloat = 28
    static let slotEntryDepth: CGFloat = 6

    public static func restPosition(for gear: Gear) -> CGPoint {
        guard let slot = gear.slot else { return CGPoint(x: columns[1], y: rail) }
        return CGPoint(x: columns[slot.column], y: slot.row == 0 ? top : bottom)
    }

    /// Where the knob ends up when dragged towards `proposed` from `current`: it slides along the
    /// rail, and only leaves it into a slot it is lined up with.
    public static func constrain(_ proposed: CGPoint, from current: CGPoint) -> CGPoint {
        if abs(current.y - rail) < railTolerance {
            let x = clamp(proposed.x, columns[0], columns[2])
            let column = nearestColumn(to: x)
            if abs(x - columns[column]) < railTolerance && abs(proposed.y - rail) > slotEntryDepth {
                return CGPoint(x: columns[column], y: clamp(proposed.y, top, bottom))
            }
            return CGPoint(x: x, y: rail)
        }
        let y = clamp(proposed.y, top, bottom)
        if abs(y - rail) < railTolerance {
            return CGPoint(x: clamp(proposed.x, columns[0], columns[2]), y: rail)
        }
        return CGPoint(x: columns[nearestColumn(to: current.x)], y: y)
    }

    /// Gear selected when the knob is let go at `point`: past the gate means the slot's gear,
    /// otherwise neutral.
    public static func gear(atRelease point: CGPoint) -> Gear {
        let column = nearestColumn(to: point.x)
        if point.y < rail - gateTolerance { return Gear.at(column: column, row: 0) ?? .neutral }
        if point.y > rail + gateTolerance { return Gear.at(column: column, row: 1) ?? .neutral }
        return .neutral
    }

    static func nearestColumn(to x: CGFloat) -> Int {
        columns.indices.min { abs(columns[$0] - x) < abs(columns[$1] - x) } ?? 1
    }

    static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(high, max(low, value))
    }
}
