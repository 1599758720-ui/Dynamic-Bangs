import AppKit

enum ScreenManager {
    private static let displayNumber = NSDeviceDescriptionKey("NSScreenNumber")

    static var menuBarHeight: CGFloat {
        targetScreen().map { safeArea(for: $0).menuBarHeight } ?? MenuBarSafeArea.minimumMenuBarHeight
    }

    /// The menu-bar band and the island's usable area on `screen`, from the
    /// public `NSScreen` geometry only (frame, visibleFrame, safeAreaInsets and
    /// the auxiliary top areas either side of the camera housing).
    static func safeArea(for screen: NSScreen) -> MenuBarSafeArea {
        MenuBarSafeArea.resolve(screenFrame: screen.frame,
                                visibleFrame: screen.visibleFrame,
                                safeTopInset: screen.safeAreaInsets.top,
                                auxiliaryLeft: screen.auxiliaryTopLeftArea,
                                auxiliaryRight: screen.auxiliaryTopRightArea,
                                statusBarThickness: NSStatusBar.system.thickness)
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[displayNumber] as? NSNumber)?.uint32Value
    }

    static func screen(withID id: CGDirectDisplayID?) -> NSScreen? {
        guard let id else { return nil }
        return NSScreen.screens.first { displayID(for: $0) == id }
    }

    static func targetScreen() -> NSScreen? {
        // Prefer the built-in notch. In clamshell mode, use the primary display.
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.screens.first
    }
}
