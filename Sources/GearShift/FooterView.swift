import SwiftUI

struct FooterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isSettingsShown = false
    @State private var turbo = TurboEgg.load()

    var body: some View {
        VStack(spacing: 8) {
            Text(model.hint)
                .font(.system(size: 10, design: .monospaced))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 8) {
                if !model.isAccessibilityTrusted {
                    Button {
                        model.openAccessibilitySettings()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.open")
                            Text("grant Accessibility")
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.amber)
                    }
                    .buttonStyle(.plain)
                    .help("GearShift needs Accessibility to switch tabs and type the commands")
                }
                if let app = model.automationDeniedApp {
                    Button {
                        model.openAutomationSettings()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.open")
                            Text("allow Automation")
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.amber)
                    }
                    .buttonStyle(.plain)
                    .help("Allow GearShift to control \(app) in System Settings › Privacy & Security › Automation")
                }
                Spacer(minLength: 0)
                if let turbo {
                    TurboButton(egg: turbo)
                }
                Button {
                    isSettingsShown.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(Palette.dim)
                }
                .buttonStyle(.plain)
                .help("Gear settings")
                .popover(isPresented: $isSettingsShown, arrowEdge: .bottom) {
                    SettingsView(isPresented: $isSettingsShown)
                }
            }
        }
    }
}
