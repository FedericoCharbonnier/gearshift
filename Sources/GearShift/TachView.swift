import SwiftUI

/// Tachometer: 0–8k tok/min over a 160° arc, redline from 6.5k. Drawn in the demo's 150×92 grid.
/// Only the needle animates; the dial and the hub are static layers below and above it.
struct TachView: View {
    let target: Double
    let color: Color
    @State private var needle = NeedleEasing()
    @Environment(\.controlActiveState) private var controlActiveState

    static let hub = CGPoint(x: 75, y: 82)

    /// Stays live while you work in the terminal, but at a lower frame rate when the app isn't
    /// frontmost (60 fps in the background cost ~15% of a core).
    private var frameInterval: Double {
        controlActiveState == .inactive ? 1.0 / 15 : 1.0 / 60
    }

    var body: some View {
        ZStack {
            TachDial()
            TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
                Canvas { context, size in
                    Self.scaleToGrid(&context, size: size)
                    drawNeedle(&context, value: needle.value(at: timeline.date, target: target))
                }
            }
            TachHub()
        }
        .frame(width: 120, height: 74)
    }

    private func drawNeedle(_ context: inout GraphicsContext, value: Double) {
        var needlePath = Path()
        needlePath.move(to: Self.hub)
        needlePath.addLine(to: Self.point(angle: Self.angle(for: value), radius: 58))
        context.addFilter(.shadow(color: color, radius: 4))
        context.stroke(needlePath, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    static func scaleToGrid(_ context: inout GraphicsContext, size: CGSize) {
        context.scaleBy(x: size.width / 150, y: size.height / 92)
    }

    static func arc(from start: Double, to end: Double) -> Path {
        var path = Path()
        let steps = 48
        for step in 0...steps {
            let point = Self.point(angle: start + (end - start) * Double(step) / Double(steps), radius: 56)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    static func angle(for tokensPerMinute: Double) -> Double {
        -80 + min(8000, max(0, tokensPerMinute)) / 8000 * 160
    }

    static func point(angle: Double, radius: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: 75 + radius * sin(radians), y: 82 - radius * cos(radians))
    }
}

/// The arcs, ticks, numbers and caption. No inputs, so SwiftUI draws it once and keeps it.
private struct TachDial: View {
    var body: some View {
        Canvas { context, size in
            TachView.scaleToGrid(&context, size: size)
            context.stroke(TachView.arc(from: -80, to: 80), with: .color(Color(hex: "#3a3d47")), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            context.stroke(TachView.arc(from: TachView.angle(for: 6500), to: 80), with: .color(Color(hex: "#e6413d")), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            for thousand in 0...8 {
                let angle = TachView.angle(for: Double(thousand) * 1000)
                var tick = Path()
                tick.move(to: TachView.point(angle: angle, radius: 50))
                tick.addLine(to: TachView.point(angle: angle, radius: 58))
                context.stroke(tick, with: .color(Color(hex: "#c9ccd3")), lineWidth: 1.4)
                if thousand.isMultiple(of: 2) {
                    let label = Text("\(thousand)").font(.system(size: 8, design: .monospaced)).foregroundColor(Color(hex: "#9a9da5"))
                    context.draw(label, at: TachView.point(angle: angle, radius: 41))
                }
            }
            let unit = Text("TOK/MIN ×1000").font(.system(size: 6.5, design: .monospaced)).foregroundColor(Color(hex: "#6a5a3c"))
            context.draw(unit, at: CGPoint(x: 75, y: 60))
        }
    }
}

/// The needle's pivot, drawn above it.
private struct TachHub: View {
    var body: some View {
        Canvas { context, size in
            TachView.scaleToGrid(&context, size: size)
            let hubRect = CGRect(x: TachView.hub.x - 5, y: TachView.hub.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: hubRect), with: .color(Color(hex: "#17181c")))
            context.stroke(Path(ellipseIn: hubRect), with: .color(Color(hex: "#55585f")), lineWidth: 1.5)
        }
    }
}

/// The demo's per-frame easing (7% of the gap per 60 fps frame) plus a small wobble.
final class NeedleEasing {
    private var value = 900.0
    private var lastDate: Date?

    func value(at date: Date, target: Double) -> Double {
        let elapsed = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        let milliseconds = date.timeIntervalSinceReferenceDate * 1000
        let wobble = sin(milliseconds / 300) * 60 + sin(milliseconds / 87) * 25
        let frames = min(elapsed * 60, 10)
        value += (target + wobble - value) * (1 - pow(0.93, frames))
        return value
    }
}
