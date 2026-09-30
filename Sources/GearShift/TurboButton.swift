import AppKit
import GearShiftCore
import SwiftUI

/// An easter egg: a red TURBO button that asks for a password and then shows an image. The image
/// ships in the app bundle (`turbo.png`) with built-in passwords. A local
/// `~/Library/Application Support/GearShift/turbo/` folder replaces either one: `image.png`, and a
/// `passwords` file with one accepted password per line.
struct TurboEgg {
    let image: NSImage
    let passwords: TurboPasswords

    static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GearShift/turbo", isDirectory: true)

    static func load() -> TurboEgg? {
        let localImage = NSImage(contentsOf: directory.appendingPathComponent("image.png"))
        let bundledImage = Bundle.main.url(forResource: "turbo", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        guard let image = localImage ?? bundledImage else { return nil }
        let localPasswords = (try? String(contentsOf: directory.appendingPathComponent("passwords"), encoding: .utf8))
            .flatMap(TurboPasswords.init(fileContents:))
        return TurboEgg(image: image, passwords: localPasswords ?? .builtIn)
    }
}

private let turboRed = Color(hex: "#e6413d")

/// Pulses and wobbles to draw the eye; shows the pointing hand on hover.
struct TurboButton: View {
    let egg: TurboEgg
    @State private var isShown = false
    @State private var isPulsing = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Text("TURBO")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(turboRed))
                .shadow(color: turboRed.opacity(isPulsing ? 0.95 : 0.3), radius: isPulsing ? 9 : 2)
                .scaleEffect(isPulsing ? 1.1 : 0.94)
                .rotationEffect(.degrees(isPulsing ? 3 : -3))
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onHover { isInside in
            if isInside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            TurboPasswordPrompt(egg: egg) {
                isShown = false
                TurboImageWindow.show(egg.image)
            }
        }
    }
}

private struct TurboPasswordPrompt: View {
    let egg: TurboEgg
    let onUnlock: () -> Void
    @State private var attempt = ""
    @State private var isWrong = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TURBO")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(turboRed)
            SecureField("password", text: $attempt)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(check)
            if isWrong {
                Text("wrong password")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Go", action: check)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
    }

    private func check() {
        if egg.passwords.accepts(attempt) {
            onUnlock()
        } else {
            isWrong = true
            attempt = ""
        }
    }
}

/// The unlocked image in its own borderless window, up to 80% of the screen and centred over
/// GearShift so it covers it. A click or Esc closes it.
@MainActor
enum TurboImageWindow {
    private static var window: NSWindow?

    static func show(_ image: NSImage) {
        close()
        let parent = NSApp.windows.first { $0.isVisible && $0.title == "GearShift" }
        let visible = (parent?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let scale = min(visible.width * 0.8 / image.size.width, visible.height * 0.8 / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let center = parent.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSPoint(x: visible.midX, y: visible.midY)
        var frame = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)

        let window = KeyableBorderlessWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TurboImageView(image: image, onClose: close))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    static func close() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Borderless windows can't take key focus by default, which Esc needs.
private final class KeyableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private struct TurboImageView: View {
    let image: NSImage
    let onClose: () -> Void
    @State private var isShown = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(turboRed, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .padding(10)
            }
            .scaleEffect(isShown ? 1 : 0.6)
            .opacity(isShown ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
            .onExitCommand(perform: onClose)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { isShown = true }
            }
    }
}
