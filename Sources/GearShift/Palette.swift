import GearShiftCore
import SwiftUI

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

extension Gear {
    var color: Color { Color(hex: colorHex) }
}

enum Palette {
    static let background = Color(hex: "#0a0a0d")
    static let ink = Color(hex: "#f0f0f3")
    static let dim = Color(hex: "#8b8e99")
    static let amber = Color(hex: "#ffb350")
    static let violet = Color(hex: "#c9a3e8")
    static let vfdGreen = Color(hex: "#8affc1")
    static let vfdTag = Color(hex: "#3e5a4b")
    static let vfdEdge = Color(hex: "#1c2b23")
    static let vfdBackground = Color(hex: "#030807")
}
