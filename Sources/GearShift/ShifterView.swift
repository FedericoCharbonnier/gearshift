import GearShiftCore
import SwiftUI

/// Metal plate with the H-pattern gate, six gear labels and a draggable knob. While a shift is in
/// flight the knob rests on its gear; if the shift fails it springs back.
struct ShifterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var knob = ShifterGeometry.restPosition(for: .neutral)
    /// Resets by itself when the drag ends or is cancelled (onEnded doesn't run on a cancel).
    @GestureState private var isDragging = false

    private let knobSpring = Animation.spring(response: 0.45, dampingFraction: 0.55)
    /// A press that moves less than this and releases on the engaged gear is a click, not a shift.
    private let clickTolerance: CGFloat = 3

    var body: some View {
        ZStack {
            plate
            slot(width: 132, height: 20, at: CGPoint(x: 118, y: 118))
            ForEach(ShifterGeometry.columns, id: \.self) { x in
                slot(width: 20, height: 132, at: CGPoint(x: x, y: 118))
            }
            ForEach(Gear.drivable, id: \.self) { gear in
                label(for: gear)
            }
            KnobView(gear: model.gear)
                .position(knob)
                .gesture(drag)
        }
        .frame(width: ShifterGeometry.size, height: ShifterGeometry.size)
        .coordinateSpace(name: "shifter")
        .disabled(!model.canShift)
        .opacity(model.hasSession ? 1 : 0.5)
        .onAppear { knob = ShifterGeometry.restPosition(for: model.knobGear) }
        .onChange(of: model.knobGear) { _, gear in
            guard !isDragging else { return }
            withAnimation(knobSpring) { knob = ShifterGeometry.restPosition(for: gear) }
        }
        .onChange(of: isDragging) { _, dragging in
            // Covers a cancelled drag; after onEnded the knob is already heading here.
            guard !dragging else { return }
            withAnimation(knobSpring) { knob = ShifterGeometry.restPosition(for: model.knobGear) }
        }
    }

    private var plate: some View {
        Circle()
            .fill(AngularGradient(
                stops: [
                    .init(color: Color(hex: "#b4b8c0"), location: 0),
                    .init(color: Color(hex: "#878b94"), location: 0.12),
                    .init(color: Color(hex: "#d3d6dc"), location: 0.25),
                    .init(color: Color(hex: "#7e828b"), location: 0.40),
                    .init(color: Color(hex: "#c3c6cd"), location: 0.55),
                    .init(color: Color(hex: "#82868f"), location: 0.70),
                    .init(color: Color(hex: "#cfd2d8"), location: 0.85),
                    .init(color: Color(hex: "#b4b8c0"), location: 1),
                ],
                center: .center,
                angle: .degrees(110)  // CSS conic "from 200deg" (0° = up) is 110° in SwiftUI (0° = right)
            ))
            .overlay(Circle().fill(RadialGradient(
                colors: [.white.opacity(0.5), .clear],
                center: UnitPoint(x: 0.38, y: 0.30),
                startRadius: 0,
                endRadius: 67
            )))
            .overlay(Circle().stroke(Color(hex: "#4a4d55")))
            .frame(width: 160, height: 160)
            .shadow(color: .black.opacity(0.6), radius: 8, y: 6)
            .position(x: 118, y: 118)
    }

    private func slot(width: CGFloat, height: CGFloat, at center: CGPoint) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: [Color(hex: "#040507"), Color(hex: "#0c0d11")], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.9), lineWidth: 2).blur(radius: 1.5))
            .shadow(color: .white.opacity(0.3), radius: 0, y: 1)
            .frame(width: width, height: height)
            .position(center)
    }

    private func label(for gear: Gear) -> some View {
        let slot = gear.slot ?? (column: 1, row: 0)
        let setting = model.config.gears[gear]
        return GearLabel(
            number: gear.rawValue,
            name: setting?.label ?? "",
            commands: setting.map { ShiftCommands.commands(for: $0)?.map(\.line).joined(separator: " · ") ?? "invalid model: fix it in settings" } ?? ""
        )
        .position(x: ShifterGeometry.columns[slot.column], y: slot.row == 0 ? 17 : 219)
        .onTapGesture { model.shift(to: gear) }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("shifter"))
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                knob = ShifterGeometry.constrain(value.location, from: knob)
            }
            .onEnded { value in
                let releaseGear = ShifterGeometry.gear(atRelease: knob)
                let distance = hypot(value.translation.width, value.translation.height)
                if distance >= clickTolerance || releaseGear != model.gear {
                    model.shift(to: releaseGear)
                }
                withAnimation(knobSpring) { knob = ShifterGeometry.restPosition(for: model.knobGear) }
            }
    }
}

struct GearLabel: View {
    let number: String
    let name: String
    /// What shifting here types, for the tooltip.
    let commands: String
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 3) {
            Text(number)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(Color(hex: "#eceef2"))
            Text(name.uppercased())
                .font(.system(size: 8, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(Color(hex: "#a2a5af"))
                .lineLimit(1)
                .allowsTightening(true)
                .minimumScaleFactor(0.7)
        }
        .padding(EdgeInsets(top: 4, leading: 4, bottom: 5, trailing: 4))
        .frame(width: 66)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: "#05070b").opacity(isHovering ? 0.92 : 0.72)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(isHovering ? Palette.amber.opacity(0.4) : .white.opacity(0.07)))
        .offset(y: isHovering ? -2 : 0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help(commands)
    }
}

struct KnobView: View {
    let gear: Gear

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(
                colors: [Color(hex: "#2c2d32"), Color(hex: "#131418"), Color(hex: "#060708")],
                center: UnitPoint(x: 0.5, y: 0.48),
                startRadius: 0,
                endRadius: 31
            ))
            Circle().fill(RadialGradient(
                colors: [.white.opacity(0.62), .clear],
                center: UnitPoint(x: 0.33, y: 0.26),
                startRadius: 0,
                endRadius: 28
            ))
            Circle().strokeBorder(
                LinearGradient(colors: [Color(hex: "#a0a5b0"), Color(hex: "#3a3d44")], startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 3
            )
            KnobPattern(gear: gear)
                .frame(width: 34, height: 40)
                .opacity(0.92)
        }
        .frame(width: 62, height: 62)
        .shadow(color: .black.opacity(0.62), radius: 12, y: 14)
    }
}

/// The H-pattern engraved on the knob with a dot on the engaged gear (demo's 40×46 grid).
struct KnobPattern: View {
    let gear: Gear

    private static let marks: [(String, CGFloat, CGFloat)] = [
        ("1", 8, 9), ("3", 20, 9), ("5", 32, 9), ("2", 8, 45), ("4", 20, 45), ("R", 32, 45),
    ]

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 40, y: size.height / 46)
            let ink = Color(hex: "#cfd2d8")
            var lines = Path()
            for x: CGFloat in [8, 20, 32] {
                lines.move(to: CGPoint(x: x, y: 12))
                lines.addLine(to: CGPoint(x: x, y: 34))
            }
            lines.move(to: CGPoint(x: 8, y: 23))
            lines.addLine(to: CGPoint(x: 32, y: 23))
            context.stroke(lines, with: .color(ink.opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for (mark, x, y) in Self.marks {
                let text = Text(mark).font(.system(size: 8, weight: .semibold)).foregroundColor(ink.opacity(0.85))
                context.draw(text, at: CGPoint(x: x, y: y - 3))
            }
            let dot = Self.dotPosition(for: gear)
            context.fill(Path(ellipseIn: CGRect(x: dot.x - 3, y: dot.y - 3, width: 6, height: 6)), with: .color(gear.color))
        }
    }

    static func dotPosition(for gear: Gear) -> CGPoint {
        guard let slot = gear.slot else { return CGPoint(x: 20, y: 23) }
        return CGPoint(x: [8, 20, 32][slot.column], y: slot.row == 0 ? 13 : 33)
    }
}
