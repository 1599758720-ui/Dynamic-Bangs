import AppKit

/// Borderless, transparent, always-on-top panel that hosts the notch island.
final class NotchPanel: NSPanel {
    var allowsKeyboardFocus = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { allowsKeyboardFocus && !SystemStatus.shared.isLocked }
    override var canBecomeMain: Bool { false }

    /// The controller fits the whole window inside the display's docking area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
