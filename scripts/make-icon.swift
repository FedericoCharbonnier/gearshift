import AppKit

// Renders the app icon (a shift knob with an H-pattern, amber dot on 5th) into an .iconset folder.
// Usage: swift scripts/make-icon.swift build/GearShift.iconset

extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

func renderIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = CGFloat(pixels) / 1024

    let tile = NSBezierPath(
        roundedRect: NSRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale),
        xRadius: 185 * scale, yRadius: 185 * scale)
    NSGradient(starting: NSColor(hex: 0x191A20), ending: NSColor(hex: 0x0C0D11))!.draw(in: tile, angle: -75)

    let knobRect = NSRect(x: 232 * scale, y: 232 * scale, width: 560 * scale, height: 560 * scale)
    NSGradient(colors: [NSColor(hex: 0x2C2D32), NSColor(hex: 0x060708)])!
        .draw(in: NSBezierPath(ovalIn: knobRect), relativeCenterPosition: NSPoint(x: -0.2, y: 0.25))
    let rim = NSBezierPath(ovalIn: knobRect.insetBy(dx: 10 * scale, dy: 10 * scale))
    rim.lineWidth = 20 * scale
    NSColor(hex: 0xA0A5B0).setStroke()
    rim.stroke()

    let pattern = NSBezierPath()
    for x: CGFloat in [392, 512, 632] {
        pattern.move(to: NSPoint(x: x * scale, y: 392 * scale))
        pattern.line(to: NSPoint(x: x * scale, y: 632 * scale))
    }
    pattern.move(to: NSPoint(x: 392 * scale, y: 512 * scale))
    pattern.line(to: NSPoint(x: 632 * scale, y: 512 * scale))
    pattern.lineWidth = 34 * scale
    pattern.lineCapStyle = .round
    NSColor(hex: 0xCFD2D8).setStroke()
    pattern.stroke()

    NSColor(hex: 0xFFB350).setFill()
    NSBezierPath(ovalIn: NSRect(x: 592 * scale, y: 592 * scale, width: 80 * scale, height: 80 * scale)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try renderIcon(pixels: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderIcon(pixels: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
