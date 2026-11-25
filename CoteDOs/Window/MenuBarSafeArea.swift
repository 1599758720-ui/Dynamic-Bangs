import CoreGraphics

/// Snapshot of a window from `CGWindowListCopyWindowInfo`, kept as pure value
/// data so menu-bar crowding math can be unit-tested without a live display.
struct MenuBarWindowSample: Equatable {
    let windowNumber: Int
    let layer: Int
    let alpha: CGFloat
    /// Bounds in CoreGraphics global display coordinates (origin top-left of
    /// the primary display, y increasing downward).
    let cgBounds: CGRect
}

/// Free horizontal space on each side of the physical camera housing inside the
/// menu-bar band, measured from public window/accessibility geometry.
struct MenuBarClearance: Equatable {
    /// Free points immediately left of `notch.minX`, or `nil` when no
    /// Accessibility measurement is available for the frontmost app's menus.
    let availableLeft: CGFloat?
    /// Free points immediately right of `notch.maxX`, measured from on-screen
    /// status-item windows (`CGWindowListCopyWindowInfo`, no permission needed).
    let availableRight: CGFloat?
    /// Rightmost x of the frontmost app's menu items (screen x), if known.
    let leftMenuRightEdge: CGFloat?
    /// Leftmost x of the on-screen status items (screen x), if known.
    let rightStatusLeftEdge: CGFloat?

    static let unconstrained = MenuBarClearance(
        availableLeft: nil, availableRight: nil,
        leftMenuRightEdge: nil, rightStatusLeftEdge: nil
    )

    /// Minimum horizontal breathing room preserved between a notch wing and
    /// the nearest macOS menu title or status bar icon.
    static let defaultSafetyGap: CGFloat = 8
    /// `CGWindowLevelForKey(.statusWindow)` — the layer where macOS places
    /// system and third-party status bar items.
    static let statusItemLayer: Int = 25

    /// Compute left/right free space around `safeArea.notch` from public
    /// `CGWindowListCopyWindowInfo` bounds (right side, zero permissions) and
    /// optional Accessibility menu-bar right edge (left side).
    static func resolve(safeArea: MenuBarSafeArea,
                        primaryScreenHeight: CGFloat,
                        windows: [MenuBarWindowSample],
                        excludedWindowNumbers: Set<Int>,
                        leftMenuRightEdgeCG: CGFloat?,
                        safetyGap: CGFloat = defaultSafetyGap) -> MenuBarClearance {
        guard let notch = safeArea.notch else { return .unconstrained }

        let cgTop = primaryScreenHeight - safeArea.screenFrame.maxY
        let cgBottom = cgTop + safeArea.menuBarHeight

        var leftmostRightStatus: CGFloat?
        for sample in windows {
            guard !excludedWindowNumbers.contains(sample.windowNumber),
                  sample.layer == statusItemLayer,
                  sample.alpha > 0.01,
                  sample.cgBounds.width > 1,
                  sample.cgBounds.height > 1 else { continue }
            // Must overlap the target display's menu-bar band vertically.
            guard sample.cgBounds.minY < cgBottom - 1,
                  sample.cgBounds.maxY > cgTop + 1 else { continue }
            // Must sit in the right auxiliary area of this display (at least
            // partially right of the camera housing, and within this screen).
            guard sample.cgBounds.maxX > notch.maxX,
                  sample.cgBounds.minX < safeArea.screenFrame.maxX,
                  sample.cgBounds.midX >= notch.midX else { continue }

            let edge = sample.cgBounds.minX
            if let existing = leftmostRightStatus {
                leftmostRightStatus = min(existing, edge)
            } else {
                leftmostRightStatus = edge
            }
        }

        let rightFree: CGFloat
        if let leftmostRightStatus {
            rightFree = max(0, leftmostRightStatus - notch.maxX - safetyGap)
        } else {
            rightFree = max(0, safeArea.screenFrame.maxX - notch.maxX - safetyGap)
        }

        let leftFree: CGFloat?
        let clampedLeftEdge: CGFloat?
        if let leftEdge = leftMenuRightEdgeCG,
           leftEdge >= safeArea.screenFrame.minX,
           leftEdge <= safeArea.screenFrame.maxX {
            clampedLeftEdge = leftEdge
            leftFree = max(0, notch.minX - leftEdge - safetyGap)
        } else {
            clampedLeftEdge = nil
            leftFree = nil
        }

        return MenuBarClearance(
            availableLeft: leftFree,
            availableRight: rightFree,
            leftMenuRightEdge: clampedLeftEdge,
            rightStatusLeftEdge: leftmostRightStatus
        )
    }

    /// True if two measurements differ enough to warrant updating layout.
    func differsSignificantly(from other: MenuBarClearance, tolerance: CGFloat = 1.5) -> Bool {
        func changed(_ a: CGFloat?, _ b: CGFloat?) -> Bool {
            switch (a, b) {
            case (nil, nil): return false
            case let (x?, y?): return abs(x - y) >= tolerance
            default: return true
            }
        }
        return changed(availableLeft, other.availableLeft)
            || changed(availableRight, other.availableRight)
    }
}

/// Desired width budget for one flanking wing of the compact notch bar.
struct NotchWingPreference: Equatable {
    /// Ideal width for the full content (e.g. artwork + title, or wave + timer).
    let desiredWidth: CGFloat
    /// Narrower acceptable width when space is tight (e.g. artwork-only or
    /// without wave). Set equal to `desiredWidth` if no compact variant exists.
    let compactWidth: CGFloat
    /// Smallest width still legible before yielding completely to macOS items.
    let minimumWidth: CGFloat

    static let empty = NotchWingPreference(desiredWidth: 0, compactWidth: 0, minimumWidth: 0)
}

/// Solved geometry for the compact bar flanking the physical camera housing at
/// menu-bar height. Every pixel drawn and every cursor hit-test comes from this.
struct NotchFlankLayout: Equatable {
    /// Exact screen-coordinate rect of the visible compact notch bar.
    let frame: CGRect
    /// Allocated left wing width (`0` when empty or yielded to app menus).
    let leftWingWidth: CGFloat
    /// Allocated right wing width (`0` when empty or yielded to status icons).
    let rightWingWidth: CGFloat
    /// Empty horizontal span inside `frame` reserved for the hardware camera.
    let cameraGapWidth: CGFloat
    /// True when the left wing should use its narrower compact layout.
    let leftCompact: Bool
    /// True when the right wing should use its narrower compact layout.
    let rightCompact: Bool
    /// True when the left wing wanted space but yielded to protect app menus.
    let leftYielded: Bool
    /// True when the right wing wanted space but yielded to protect status icons.
    let rightYielded: Bool
    /// Outward concave top flare radius on each side (`0` when that side has no wing).
    let leadingTopFlare: CGFloat
    let trailingTopFlare: CGFloat

    var height: CGFloat { frame.height }
    var hasVisibleWings: Bool { leftWingWidth > 0 || rightWingWidth > 0 }
    /// When a transient alert/HUD cannot fit beside a crowded menu bar, drop
    /// it cleanly beneath the notch rather than truncating or covering icons.
    var shouldDropDownTransientActivity: Bool { leftYielded || rightYielded }

    /// Inset kept inside the hardware notch when a wing is absent (`0pt`), so
    /// adjacent status items' control padding is never touched.
    static let passiveNotchInset: CGFloat = 6
    static let topFlareRadius: CGFloat = 6
    static let hoverGrowth: CGFloat = 3
    /// Conservative fraction of the left auxiliary area used as a ceiling when
    /// Accessibility permission is not granted.
    static let fallbackLeftAuxiliaryFraction: CGFloat = 0.22

    static func solve(safeArea: MenuBarSafeArea,
                      clearance: MenuBarClearance,
                      left: NotchWingPreference,
                      right: NotchWingPreference,
                      heightExtra: CGFloat = 0,
                      hovering: Bool = false) -> NotchFlankLayout? {
        guard let notch = safeArea.notch else { return nil }

        let leftAuxWidth = max(0, notch.minX - safeArea.screenFrame.minX)
        let rightAuxWidth = max(0, safeArea.screenFrame.maxX - notch.maxX)
        let leftHardLimit = max(0, leftAuxWidth - 16)
        let rightHardLimit = max(0, rightAuxWidth - 16)

        let maxLeft: CGFloat
        if let measuredLeft = clearance.availableLeft {
            maxLeft = min(leftHardLimit, max(0, measuredLeft))
        } else {
            maxLeft = min(leftHardLimit, floor(leftAuxWidth * fallbackLeftAuxiliaryFraction))
        }

        let maxRight: CGFloat
        if let measuredRight = clearance.availableRight {
            maxRight = min(rightHardLimit, max(0, measuredRight))
        } else {
            maxRight = min(rightHardLimit, floor(rightAuxWidth * fallbackLeftAuxiliaryFraction))
        }

        func allocate(_ pref: NotchWingPreference, limit: CGFloat) -> (width: CGFloat, compact: Bool, yielded: Bool) {
            guard pref.desiredWidth > 0 else { return (0, false, false) }
            let extra = hovering ? hoverGrowth : 0
            if pref.desiredWidth <= limit {
                return (min(limit, pref.desiredWidth + extra), false, false)
            }
            if pref.compactWidth > 0, pref.compactWidth <= limit {
                return (min(limit, pref.compactWidth + extra), true, false)
            }
            if pref.minimumWidth > 0, pref.minimumWidth <= limit {
                return (limit, true, false)
            }
            return (0, false, true)
        }

        let solvedLeft = allocate(left, limit: maxLeft)
        let solvedRight = allocate(right, limit: maxRight)

        let passiveInset = min(passiveNotchInset, max(0, notch.width / 4))
        let minX = solvedLeft.width > 0 ? notch.minX - solvedLeft.width : notch.minX + passiveInset
        let maxX = solvedRight.width > 0 ? notch.maxX + solvedRight.width : notch.maxX - passiveInset
        let height = min(safeArea.screenFrame.height,
                         max(notch.height, safeArea.menuBarHeight + heightExtra))
        let frame = CGRect(x: minX, y: safeArea.screenFrame.maxY - height,
                           width: max(0, maxX - minX), height: height)
        let cameraGap = max(0, frame.width - solvedLeft.width - solvedRight.width)

        return NotchFlankLayout(
            frame: frame,
            leftWingWidth: solvedLeft.width,
            rightWingWidth: solvedRight.width,
            cameraGapWidth: cameraGap,
            leftCompact: solvedLeft.compact,
            rightCompact: solvedRight.compact,
            leftYielded: solvedLeft.yielded,
            rightYielded: solvedRight.yielded,
            leadingTopFlare: solvedLeft.width > 0 ? topFlareRadius : 0,
            trailingTopFlare: solvedRight.width > 0 ? topFlareRadius : 0
        )
    }
}

/// Display geometry in AppKit screen coordinates.
///
/// - On a notched display at `.home`, the collapsed bar flanks the physical
///   camera housing inside `menuBarBand` using only the free space verified by
///   `MenuBarClearance`, while the expanded workbench always opens below
///   `menuBarBand` inside `dockingFrame`.
/// - On non-notched displays, or when the user drags the island off `.home`,
///   both compact and expanded surfaces live strictly inside `dockingFrame`.
struct MenuBarSafeArea: Equatable {
    /// The whole display.
    let screenFrame: CGRect
    /// The band the menu bar occupies — always full width, top-aligned.
    let menuBarBand: CGRect
    /// The camera housing on a notched built-in display, nil elsewhere.
    let notch: CGRect?

    /// Where floating surfaces and the expanded workbench live: the display
    /// minus the menu-bar band. The top edge of this rect is the menu bar's
    /// lower edge.
    var dockingFrame: CGRect {
        CGRect(x: screenFrame.minX, y: screenFrame.minY,
               width: screenFrame.width, height: max(0, screenFrame.height - menuBarBand.height))
    }

    /// Height of the band reserved for the menu bar.
    var menuBarHeight: CGFloat { menuBarBand.height }

    /// Smallest band we ever reserve. Matches the classic non-notched menu bar.
    static let minimumMenuBarHeight: CGFloat = 24
    /// Anything larger than this read off `visibleFrame` is not a menu bar.
    static let maximumPlausibleMenuBarHeight: CGFloat = 80

    /// Resolve the band from public `NSScreen` values.
    static func resolve(screenFrame: CGRect,
                        visibleFrame: CGRect,
                        safeTopInset: CGFloat,
                        auxiliaryLeft: CGRect?,
                        auxiliaryRight: CGRect?,
                        statusBarThickness: CGFloat) -> MenuBarSafeArea {
        let reserved = screenFrame.maxY - visibleFrame.maxY
        let validReserved = (reserved > 0 && reserved < maximumPlausibleMenuBarHeight) ? reserved : 0
        // Keep the border below the camera housing reserved when the bar hides.
        let housingBand = safeTopInset > 0 ? safeTopInset + 1 : 0
        let height = min(screenFrame.height, max(minimumMenuBarHeight, housingBand, statusBarThickness, validReserved))
        let band = CGRect(x: screenFrame.minX, y: screenFrame.maxY - height,
                          width: screenFrame.width, height: height)
        var notch: CGRect?
        if safeTopInset > 0, let left = auxiliaryLeft, let right = auxiliaryRight, right.minX > left.maxX {
            notch = CGRect(x: left.maxX, y: screenFrame.maxY - safeTopInset,
                           width: right.minX - left.maxX, height: safeTopInset)
        }
        return MenuBarSafeArea(screenFrame: screenFrame, menuBarBand: band, notch: notch)
    }

    func intrudesMenuBar(_ rect: CGRect) -> Bool {
        guard !rect.isNull, !rect.isEmpty else { return false }
        let overlap = rect.intersection(menuBarBand)
        return !overlap.isNull && overlap.width > 0.5 && overlap.height > 0.5
    }

    func clippedBelowMenuBar(_ rect: CGRect) -> CGRect {
        rect.intersection(dockingFrame)
    }

    /// Host panel frame in Notch-Flanking Mode: top edge flush with the screen
    /// top so the compact wings align with the physical notch, while the lower
    /// portion of the same panel hosts the expanded workbench below the menu bar.
    func notchPanelFrame(size: CGSize) -> CGRect {
        let fitted = CGSize(width: min(size.width, screenFrame.width),
                            height: min(size.height, screenFrame.height))
        let centreX = notch?.midX ?? screenFrame.midX
        let x = min(max(screenFrame.minX, centreX - fitted.width / 2),
                    screenFrame.maxX - fitted.width)
        let y = screenFrame.maxY - fitted.height
        return CGRect(x: x, y: y, width: fitted.width, height: fitted.height)
    }

    /// Expanded workbench card rect when anchored under the physical notch.
    /// Always sits strictly below `menuBarBand.minY` so left app menus and
    /// right status icons stay visible and clickable even while expanded.
    func expandedWorkbenchRect(inPanel panel: CGRect, size: CGSize, topGap: CGFloat) -> CGRect {
        let width = min(size.width, dockingFrame.width, panel.width)
        let availableHeight = max(0, min(dockingFrame.height - topGap, panel.height))
        let height = min(size.height, availableHeight)
        let centreX = notch?.midX ?? panel.midX
        let x = min(max(panel.minX, centreX - width / 2), panel.maxX - width)
        let maxY = min(dockingFrame.maxY - topGap, panel.maxY)
        let y = max(dockingFrame.minY, maxY - height)
        return CGRect(x: x, y: y, width: width, height: max(0, min(height, maxY - y)))
    }

    /// Compact floating pill dropped directly beneath the camera notch when
    /// a transient activity cannot fit beside a crowded menu bar.
    func activityDropDownRect(inPanel panel: CGRect, size: CGSize, topGap: CGFloat) -> CGRect {
        expandedWorkbenchRect(inPanel: panel, size: size, topGap: topGap)
    }

    /// Constrain the floating panel (external display, non-notched display, or
    /// user-dragged placement) strictly inside `dockingFrame`.
    func panelFrame(placement: NotchPlacement, size: CGSize, dragOrigin: CGPoint? = nil) -> CGRect {
        let bounds = dockingFrame
        let fitted = CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        let docked = placement.panelFrame(screen: bounds, panelSize: fitted)
        var origin = dragOrigin ?? docked.origin
        if dragOrigin == nil, placement.isHome, let notch {
            origin.x = notch.midX - fitted.width / 2
        }
        origin.x = min(max(bounds.minX, origin.x), bounds.maxX - fitted.width)
        origin.y = min(max(bounds.minY, origin.y), bounds.maxY - fitted.height)
        return CGRect(origin: origin, size: fitted)
    }
}

/// Pure sizing of the floating compact capsule (used on non-notched displays,
/// off-home user placements, and dropped-down transient activities).
enum IslandFootprint {
    static func compactWidth(notchWidth: CGFloat, hasContent: Bool, isPlaying: Bool, hovering: Bool) -> CGFloat {
        let base = min(248, max(170, notchWidth))
        let width = isPlaying ? base + 56 : (hasContent ? base : 76)
        return width + (hovering ? 6 : 0)
    }
}
