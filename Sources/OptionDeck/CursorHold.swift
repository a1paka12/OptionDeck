import CoreGraphics

/// Suppressing CGEvents does not stop WindowServer from moving the pointer.
/// Pin its physical position as well, without activating the panel's app.
@MainActor
final class CursorHold {
    private var anchor: CGPoint?
    private var hidden = false

    func begin() {
        guard anchor == nil, let event = CGEvent(source: nil) else { return }
        anchor = CGPoint(x: event.location.x.rounded(), y: event.location.y.rounded())
        hidden = CGDisplayHideCursor(CGMainDisplayID()) == .success
        pin()
    }
    func pin() {
        guard let anchor else { return }
        CGWarpMouseCursorPosition(anchor)
    }
    func end() {
        if let anchor { CGWarpMouseCursorPosition(anchor) }
        anchor = nil
        if hidden { CGDisplayShowCursor(CGMainDisplayID()) }
        hidden = false
    }
}
