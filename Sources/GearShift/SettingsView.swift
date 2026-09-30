import GearShiftCore
import SwiftUI

/// Edit what each gear types into the session. Changes apply on Save, from the next shift on.
struct SettingsView: View {
    /// Top to bottom: reverse, neutral, then the forward gears.
    static let rows: [Gear] = [.reverse, .neutral, .one, .two, .three, .four, .five]

    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var draft: [Gear: GearSetting] = [:]
    @State private var isMuted = false
    @State private var keepsOnTop = true
    @State private var returnsToPreviousApp = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GEARS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Palette.dim)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("Label")
                    Text("Readout")
                    Text("Model")
                    Text("Effort")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.dim)
                ForEach(Self.rows, id: \.self) { gear in
                    GridRow {
                        Text(gear.rawValue)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(gear.color)
                        TextField("", text: binding(gear, \.label)).frame(width: 110)
                        TextField("", text: binding(gear, \.displayName)).frame(width: 135)
                        TextField("e.g. sonnet", text: binding(gear, \.model))
                            .frame(width: 80)
                            .foregroundStyle(ShiftCommands.isValidModel(setting(for: gear).model) ? Color.primary : Color.red)
                            .help("A model alias or id: letters, digits and . _ : [ ] -")
                        Picker("", selection: binding(gear, \.effort)) {
                            Text("auto").tag(Effort?.none)
                            ForEach(Effort.allCases, id: \.self) { Text($0.rawValue).tag(Effort?.some($0)) }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            Toggle("Mute shift sounds", isOn: $isMuted)
                .font(.system(size: 11))
            Toggle("Keep GearShift above other windows", isOn: $keepsOnTop)
                .font(.system(size: 11))
            Toggle("Return to where I was after shifting (Warp, Terminal)", isOn: $returnsToPreviousApp)
                .font(.system(size: 11))
                .help("Warp and Terminal come to the front to be typed into; this brings back the app, window and tab you were on. iTerm2 is typed into in the background.")
            HStack {
                if !areModelsValid {
                    Text("fix the models in red")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Save") {
                    // Every gear, even one missing from a hand-edited config.
                    let gears = Dictionary(uniqueKeysWithValues: Self.rows.map { ($0, setting(for: $0)) })
                    model.updateSettings(gears: gears, isMuted: isMuted, keepsOnTop: keepsOnTop, returnsToPreviousApp: returnsToPreviousApp)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!areModelsValid)
            }
        }
        .padding(16)
        .onAppear {
            draft = model.config.gears
            isMuted = model.config.isMuted
            keepsOnTop = model.config.keepsOnTop
            returnsToPreviousApp = model.config.returnsToPreviousApp
        }
    }

    /// Save stays off while any model would be refused when shifting.
    private var areModelsValid: Bool {
        Self.rows.allSatisfy { ShiftCommands.isValidModel(setting(for: $0).model) }
    }

    private func binding<Value>(_ gear: Gear, _ keyPath: WritableKeyPath<GearSetting, Value>) -> Binding<Value> {
        Binding(
            get: { setting(for: gear)[keyPath: keyPath] },
            set: { newValue in
                var updated = setting(for: gear)
                updated[keyPath: keyPath] = newValue
                draft[gear] = updated
            }
        )
    }

    private func setting(for gear: Gear) -> GearSetting {
        draft[gear] ?? GearConfig.defaults.gears[gear] ?? GearSetting(label: "", displayName: "", model: "")
    }
}
