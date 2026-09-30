import AppKit
import SwiftUI

/// Floats the shifter above other apps' windows, on every Space and over full-screen terminals,
/// so it stays in view after a shift hands keyboard focus to the terminal.
struct WindowLevel: NSViewRepresentable {
    let floats: Bool

    private static let floatingBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        // The view only gets its window after the first layout pass.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = floats ? .floating : .normal
            if floats {
                window.collectionBehavior.formUnion(Self.floatingBehavior)
            } else {
                window.collectionBehavior.subtract(Self.floatingBehavior)
            }
        }
    }
}
