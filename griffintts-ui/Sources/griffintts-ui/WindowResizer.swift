import AppKit
import SwiftUI

/// An invisible NSViewRepresentable whose sole purpose is to resize the
/// host NSWindow whenever `width` changes. SwiftUI's .frame() modifier only
/// constrains the layout engine, not the actual AppKit window frame, so we
/// need this AppKit bridge to perform the real window resize.
struct WindowResizer: NSViewRepresentable {
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            var frame = window.frame
            let deltaX = width - frame.width
            // Expand to the right (keep top-left corner fixed by adjusting origin.x by half)
            frame.origin.x -= deltaX
            frame.size.width = width
            frame.size.height = height
            window.setFrame(frame, display: true, animate: true)
        }
    }
}
