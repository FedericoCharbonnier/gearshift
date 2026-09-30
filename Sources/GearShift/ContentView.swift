import GearShiftCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            BackdropView(gear: model.gear, isRedlining: model.isRedlining)
                .ignoresSafeArea()  // also fill the transparent title bar
            VStack(spacing: 14) {
                ClusterView()
                VFDView()
                ShifterView()
                    .padding(.vertical, 4)  // gear labels overhang the 236 pt square slightly
                FooterView()
            }
            .padding(EdgeInsets(top: 22, leading: 26, bottom: 18, trailing: 26))
            .frame(width: 288)
            .background(CardBackground())
            .modifier(Shake(animatableData: CGFloat(model.redlineCount)))
            .animation(.linear(duration: 0.4), value: model.redlineCount)
            .padding(40)
        }
        .fixedSize()
        .background(WindowLevel(floats: model.config.keepsOnTop))
    }
}

/// Frame rate for the decorative glow and road; they stop while GearShift isn't the active app.
enum AmbientAnimation {
    static let minimumInterval = 1.0 / 30

    static func isPaused(_ state: ControlActiveState) -> Bool {
        state == .inactive
    }
}

/// The card: dark gradient panel with a slowly spinning amber/violet glow behind its edge.
struct CardBackground: View {
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ZStack {
            TimelineView(.animation(
                minimumInterval: AmbientAnimation.minimumInterval,
                paused: AmbientAnimation.isPaused(controlActiveState)
            )) { timeline in
                let degrees = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 7) / 7 * 360
                RoundedRectangle(cornerRadius: 27)
                    .fill(AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.65),
                            .init(color: Palette.amber.opacity(0.5), location: 0.78),
                            .init(color: Palette.violet.opacity(0.5), location: 0.88),
                            .init(color: .clear, location: 0.96),
                            .init(color: .clear, location: 1),
                        ],
                        center: .center,
                        angle: .degrees(degrees - 90)
                    ))
                    .padding(-1)
                    .blur(radius: 6)
                    .opacity(0.55)
            }
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#191a20"), location: 0),
                        .init(color: Color(hex: "#101116"), location: 0.55),
                        .init(color: Color(hex: "#0c0d11"), location: 1),
                    ],
                    startPoint: UnitPoint(x: 0.37, y: 0),
                    endPoint: UnitPoint(x: 0.63, y: 1)
                ))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.09)))
                .shadow(color: .black.opacity(0.65), radius: 45, y: 40)
        }
    }
}

/// Background glows plus road stripes that scroll faster in higher gears (backwards in R).
struct BackdropView: View {
    let gear: Gear
    let isRedlining: Bool
    @State private var road = RoadScroll()
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ZStack {
            Palette.background
            RadialGradient(colors: [Palette.violet.opacity(0.10), .clear], center: UnitPoint(x: 0.78, y: 0.4), startRadius: 0, endRadius: 320)
            RadialGradient(colors: [Palette.amber.opacity(0.07), .clear], center: UnitPoint(x: 0.15, y: 0.85), startRadius: 0, endRadius: 260)
            TimelineView(.animation(
                minimumInterval: AmbientAnimation.minimumInterval,
                paused: AmbientAnimation.isPaused(controlActiveState)
            )) { timeline in
                Canvas { context, size in
                    let offset = road.offset(at: timeline.date, period: Self.period(for: gear), reversed: gear == .reverse)
                    var y = offset - RoadScroll.spacing
                    while y < size.height {
                        context.fill(Path(CGRect(x: 0, y: y + 46, width: size.width, height: 2)), with: .color(.white.opacity(0.035)))
                        y += RoadScroll.spacing
                    }
                }
            }
            .opacity(isRedlining ? 0.5 : 0.28)
        }
    }

    /// Seconds for the road to move one stripe, per gear (from the web demo).
    static func period(for gear: Gear) -> Double {
        switch gear {
        case .neutral: 7
        case .one: 3.4
        case .two: 2.3
        case .three: 1.6
        case .four: 1
        case .five: 0.55
        case .reverse: 4.5
        }
    }
}

/// Accumulates the stripe offset so changing speed doesn't make the road jump.
final class RoadScroll {
    static let spacing = 48.0
    private var offset = 0.0
    private var lastDate: Date?

    func offset(at date: Date, period: Double, reversed: Bool) -> Double {
        let elapsed = min(lastDate.map { date.timeIntervalSince($0) } ?? 0, 0.1)
        lastDate = date
        offset += (reversed ? -1 : 1) * Self.spacing * elapsed / period
        offset = offset.truncatingRemainder(dividingBy: Self.spacing)
        if offset < 0 {
            offset += Self.spacing
        }
        return offset
    }
}

/// Brief shake when redlining; animate `animatableData` from n to n + 1.
struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let phase = animatableData * .pi
        return ProjectionTransform(CGAffineTransform(translationX: 2 * sin(phase * 4), y: sin(phase * 6)))
    }
}
