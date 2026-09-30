import GearShiftCore
import SwiftUI

struct ClusterView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            TachView(target: model.needleTarget, color: model.gear.color)
            ReadoutView(gear: model.gear, title: model.readoutTitle, command: model.readoutCommand)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#04060a")))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#23252c")))
    }
}

struct ReadoutView: View {
    let gear: Gear
    let title: String
    let command: String
    @State private var isPopped = false

    var body: some View {
        VStack(spacing: 0) {
            Text(gear.rawValue)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(gear.color)
                .shadow(color: gear.color.opacity(0.53), radius: 9)
                .scaleEffect(isPopped ? 1.28 : 1)
            Text(title)
                .font(.system(size: 11, design: .monospaced))
                .tracking(2.5)
                .foregroundStyle(gear.color)
                .opacity(0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // The readout column is only ~74 pt wide: word joiners stop breaks after `-` in a model
            // name, and the second line is always reserved so the window doesn't change height.
            Text(command.replacingOccurrences(of: "-", with: "-\u{2060}"))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.8)
                .truncationMode(.tail)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: gear)
        .onChange(of: gear) { _, _ in
            withAnimation(.spring(response: 0.12, dampingFraction: 0.6)) { isPopped = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) { isPopped = false }
            }
        }
    }
}
