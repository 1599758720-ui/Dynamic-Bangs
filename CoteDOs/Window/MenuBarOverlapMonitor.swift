import AppKit
import ApplicationServices

/// Tracks available horizontal clearance on both sides of the physical camera
/// notch so compact wings never cover macOS status bar icons or app menus.
///
/// - **Right side (status icons)**: read via `CGWindowListCopyWindowInfo`
///   (layer 25 status-item windows). Works with **no Accessibility or Screen
///   Recording permission** on macOS 14–26.
/// - **Left side (frontmost app menus)**: read via the Accessibility API when
///   `AXIsProcessTrusted()` is granted. Without Accessibility permission,
///   `availableLeft` stays `nil` and `NotchFlankLayout` applies a conservative
///   fallback cap.
final class MenuBarOverlapMonitor {
    var onChange: ((MenuBarClearance) -> Void)?
    var targetGeometryProvider: (() -> MenuBarSafeArea?)?
    var excludedWindowNumbersProvider: (() -> Set<Int>)?

    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var pollTimer: Timer?
    private(set) var clearance: MenuBarClearance = .unconstrained

    private static let pollInterval: TimeInterval = 1.5

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard pollTimer == nil else {
            refreshNow()
            return
        }
        let ws = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        workspaceObservers = names.map { name in
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.evaluate()
            }
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluate()
        }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        timer.tolerance = 0.5
        pollTimer = timer
        evaluate()
    }

    func stop() {
        let ws = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(ws.removeObserver)
        workspaceObservers.removeAll()
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
    }

    deinit { stop() }

    func refreshNow() {
        evaluate(force: true)
    }

    private func evaluate(force: Bool = false) {
        let next = measureClearance()
        guard force || next.differsSignificantly(from: clearance) else { return }
        clearance = next
        onChange?(next)
    }

    private func measureClearance() -> MenuBarClearance {
        guard let safeArea = targetGeometryProvider?(), safeArea.notch != nil else {
            return .unconstrained
        }
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? safeArea.screenFrame.height
        let excluded = excludedWindowNumbersProvider?() ?? []
        let windows = Self.sampleOnScreenWindows()
        let leftEdge = Self.frontmostMenuRightEdgeCG(safeArea: safeArea, primaryScreenHeight: primaryHeight)

        return MenuBarClearance.resolve(
            safeArea: safeArea,
            primaryScreenHeight: primaryHeight,
            windows: windows,
            excludedWindowNumbers: excluded,
            leftMenuRightEdgeCG: leftEdge
        )
    }

    private static func sampleOnScreenWindows() -> [MenuBarWindowSample] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        var samples: [MenuBarWindowSample] = []
        samples.reserveCapacity(24)
        for info in raw {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == MenuBarClearance.statusItemLayer,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let number = info[kCGWindowNumber as String] as? Int else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? CGFloat)
                ?? CGFloat((info[kCGWindowAlpha as String] as? Double) ?? 1)
            samples.append(MenuBarWindowSample(
                windowNumber: number,
                layer: layer,
                alpha: alpha,
                cgBounds: bounds
            ))
        }
        return samples
    }

    /// Reads the rightmost top-level menu item edge of the frontmost app on
    /// `safeArea`'s display via Accessibility (returns `nil` without AX).
    private static func frontmostMenuRightEdgeCG(safeArea: MenuBarSafeArea,
                                                 primaryScreenHeight: CGFloat) -> CGFloat? {
        guard AXIsProcessTrusted(),
              let notch = safeArea.notch,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBarElement = menuBarValue,
              CFGetTypeID(menuBarElement) == AXUIElementGetTypeID() else { return nil }
        let menuBar = unsafeDowncast(menuBarElement, to: AXUIElement.self)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement],
              !children.isEmpty else { return nil }

        let cgTop = primaryScreenHeight - safeArea.screenFrame.maxY
        let cgBottom = cgTop + safeArea.menuBarHeight
        var maxRightEdge: CGFloat?

        for child in children {
            var posVal: CFTypeRef?
            var sizeVal: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posVal) == .success,
                  AXUIElementCopyAttributeValue(child, kAXSizeAttribute as CFString, &sizeVal) == .success,
                  let posVal, CFGetTypeID(posVal) == AXValueGetTypeID(),
                  let sizeVal, CFGetTypeID(sizeVal) == AXValueGetTypeID() else { continue }
            var pos = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(unsafeDowncast(posVal, to: AXValue.self), .cgPoint, &pos),
                  AXValueGetValue(unsafeDowncast(sizeVal, to: AXValue.self), .cgSize, &size),
                  size.width > 1, size.height > 1 else { continue }

            // Only consider menu items sitting on the target display's menu bar
            // and belonging to the left app-menu region (left of notch right edge).
            guard pos.y < cgBottom, pos.y + size.height > cgTop,
                  pos.x >= safeArea.screenFrame.minX,
                  pos.x < notch.maxX else { continue }

            let right = pos.x + size.width
            if let existing = maxRightEdge {
                maxRightEdge = max(existing, right)
            } else {
                maxRightEdge = right
            }
        }
        return maxRightEdge
    }
}
