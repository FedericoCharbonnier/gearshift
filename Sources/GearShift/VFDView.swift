import GearShiftCore
import SwiftUI

/// Green vacuum-fluorescent "SESSION" strip; click to pick the connected session to drive.
struct VFDView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isPickerShown = false

    var body: some View {
        Button {
            isPickerShown.toggle()
        } label: {
            HStack(spacing: 7) {
                Text("SESSION")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Palette.vfdTag)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Palette.vfdEdge))
                if let session = model.selectedSession {
                    SessionDot(color: model.color(for: session), size: 6)
                    VStack(alignment: .leading, spacing: 1) {
                        vfdText(model.displayName(for: session))
                        // Cut in the middle: the model at the end matters most.
                        Text(model.sessionDetail(for: session))
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.vfdGreen.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    vfdText("run /gearshift in Claude")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                BlinkingTick()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.vfdBackground))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.vfdEdge))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -4)
        .popover(isPresented: $isPickerShown, arrowEdge: .bottom) {
            SessionPicker(isPresented: $isPickerShown)
        }
    }

    private func vfdText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Palette.vfdGreen)
            .shadow(color: Palette.vfdGreen.opacity(0.45), radius: 4)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// The session's own colour, a small glowing dot.
struct SessionDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.7), radius: 2.5)
    }
}

struct BlinkingTick: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.6)) { timeline in
            let isOn = Int(timeline.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
            RoundedRectangle(cornerRadius: 1)
                .fill(Palette.vfdGreen)
                .frame(width: 3, height: 9)
                .shadow(color: Palette.vfdGreen.opacity(0.7), radius: 2.5)
                .opacity(isOn ? 1 : 0.15)
        }
    }
}

/// The connected sessions, newest first: colour and name (the Claude title dimmed after a
/// nickname), then terminal · folder · branch · model, then the last thing the user asked.
struct SessionPicker: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.sessions, id: \.sessionId) { session in
                Button {
                    model.selectSession(session.sessionId)
                    isPresented = false
                } label: {
                    row(for: session)
                }
            }
            if !model.sessions.isEmpty {
                Divider()
            }
            Text(model.sessions.isEmpty
                ? "Run /gearshift in a Claude session to connect it"
                : "Tip: /gearshift <nickname> in another session adds it")
                .foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, design: .monospaced))
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    private func row(for session: SessionRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .opacity(session.sessionId == model.selectedSessionId ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    SessionDot(color: model.color(for: session))
                    nameLine(for: session)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(model.pickerDetail(for: session))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let prompt = model.lastPrompt(for: session) {
                    Text(prompt)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.dim.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The nickname in bold, followed by the Claude title dimmed; without a nickname, the title.
    private func nameLine(for session: SessionRecord) -> Text {
        let name = Text(model.displayName(for: session)).bold()
        guard session.nickname != nil, let title = model.claudeTitle(for: session) else { return name }
        return name + Text("  " + title).foregroundColor(Palette.dim)
    }
}
