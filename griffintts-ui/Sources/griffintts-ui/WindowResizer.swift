import AppKit
import SwiftUI

/// Resizes the host NSWindow when `targetWidth` or `targetHeight` change.
///
/// KEY DESIGN DECISIONS to avoid the NSGenericException constraint loop:
///
/// 1. Guard: only call setFrame if the window size is actually different.
///    If SwiftUI re-renders without a real size change, we do nothing.
///
/// 2. Dispatch AFTER the current layout pass: calling setFrame() synchronously
///    inside updateNSView() triggers another layout pass, which calls
///    updateNSView() again, creating an unbounded recursive loop that AppKit
///    eventually terminates with "more Update Constraints passes than views".
///    Dispatching to the next main-queue cycle breaks the recursion.
///
/// 3. The root ContentView must NOT also constrain itself with
///    .frame(width: targetWidth, height: ...) — conflicting constraints
///    between SwiftUI layout and AppKit both trying to own the window size
///    is the second cause of the loop. ContentView uses .frame(minWidth:)
///    for layout hints only, not fixed sizing.
struct WindowResizer: NSViewRepresentable {
    let targetWidth: CGFloat
    let targetHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Dispatch to next run-loop cycle to avoid re-entrancy during layout
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let current = window.frame.size
            // Guard: skip if already at target size (prevents recursion)
            guard abs(current.width  - self.targetWidth)  > 1 ||
                  abs(current.height - self.targetHeight) > 1
            else { return }

            var frame = window.frame
            let deltaW = self.targetWidth - frame.width
            // Keep the top-left corner fixed by offsetting origin.x
            frame.origin.x -= deltaW
            frame.size = CGSize(width: self.targetWidth, height: self.targetHeight)
            window.setFrame(frame, display: true, animate: true)
        }
    }
}
