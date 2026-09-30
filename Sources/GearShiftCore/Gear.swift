import Foundation

/// A position of the shift lever. Each gear, neutral included, maps to one model + effort.
public enum Gear: String, CaseIterable, Codable, CodingKeyRepresentable {
    case neutral = "N"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case reverse = "R"

    /// Gears with a slot in the H-pattern, in shifter order.
    public static let drivable: [Gear] = [.one, .two, .three, .four, .five, .reverse]

    /// Column (0...2) and row (0 = top, 1 = bottom) of the gear's slot end in the H-pattern.
    /// Neutral sits in the middle of the rail and has no slot.
    public var slot: (column: Int, row: Int)? {
        switch self {
        case .neutral: nil
        case .one: (0, 0)
        case .three: (1, 0)
        case .five: (2, 0)
        case .two: (0, 1)
        case .four: (1, 1)
        case .reverse: (2, 1)
        }
    }

    /// The gear at a slot end.
    public static func at(column: Int, row: Int) -> Gear? {
        drivable.first { $0.slot?.column == column && $0.slot?.row == row }
    }

    /// Fixed accent colour, as hex RGB.
    public var colorHex: String {
        switch self {
        case .neutral, .three: "#c9a3e8"
        case .one: "#8fe3a4"
        case .two: "#7cc4e8"
        case .four: "#e8c07c"
        case .five: "#8fd8cf"
        case .reverse: "#d5d8dd"
        }
    }

    /// Tokens/min the tach needle jumps to for a moment after shifting into this gear.
    public var shiftKick: Double {
        switch self {
        case .neutral: 900
        case .one: 3600
        case .two: 4300
        case .three: 4950
        case .four: 5600
        case .five: 6900
        case .reverse: 3300
        }
    }
}
