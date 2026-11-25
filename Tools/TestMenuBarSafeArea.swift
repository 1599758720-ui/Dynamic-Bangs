import CoreGraphics

// Run with MenuBarSafeArea.swift and NotchPlacement.swift.
@main
struct TestMenuBarSafeArea {
    static func main() {
        let builtIn = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let auxLeft = CGRect(x: 0, y: 1131, width: 790, height: 38)
        let auxRight = CGRect(x: 1010, y: 1131, width: 790, height: 38)
        let visible = CGRect(x: 0, y: 83, width: 1800, height: 1047)
        let notched = MenuBarSafeArea.resolve(
            screenFrame: builtIn, visibleFrame: visible, safeTopInset: 38,
            auxiliaryLeft: auxLeft, auxiliaryRight: auxRight, statusBarThickness: 24
        )
        precondition(notched.menuBarHeight == 39 && notched.notch == CGRect(x: 790, y: 1131, width: 220, height: 38))

        // 1. Live macOS 26 status-item window layout (leftmost status item at x=1137).
        let liveWindows: [MenuBarWindowSample] = [
            // Our own panel (must be excluded so it never fights itself)
            MenuBarWindowSample(windowNumber: 9001, layer: 25, alpha: 1, cgBounds: CGRect(x: 740, y: 0, width: 350, height: 39)),
            // System & third-party status items on the right
            MenuBarWindowSample(windowNumber: 11866, layer: 25, alpha: 1, cgBounds: CGRect(x: 1137, y: 0, width: 34, height: 39)),
            MenuBarWindowSample(windowNumber: 8068, layer: 25, alpha: 1, cgBounds: CGRect(x: 1171, y: 0, width: 32, height: 39)),
            MenuBarWindowSample(windowNumber: 20, layer: 25, alpha: 1, cgBounds: CGRect(x: 1643, y: 0, width: 159, height: 39)),
            // Window Server menubar at layer 24 (must be ignored)
            MenuBarWindowSample(windowNumber: 28, layer: 24, alpha: 1, cgBounds: CGRect(x: 0, y: 0, width: 1800, height: 39)),
            // Invisible layer-25 helper (alpha 0, must be ignored)
            MenuBarWindowSample(windowNumber: 7777, layer: 25, alpha: 0, cgBounds: CGRect(x: 1015, y: 0, width: 30, height: 39)),
        ]
        let normalClearance = MenuBarClearance.resolve(
            safeArea: notched,
            primaryScreenHeight: builtIn.height,
            windows: liveWindows,
            excludedWindowNumbers: [9001],
            leftMenuRightEdgeCG: nil
        )
        precondition(normalClearance.rightStatusLeftEdge == 1137)
        precondition(normalClearance.availableRight == 119) // 1137 - 1010 - 8
        precondition(normalClearance.availableLeft == nil)

        // 2. Normal flanking: CPU rings on left (48pt) + Timer on right (72pt) sit
        //    flush at top inside the menu bar beside the hardware notch.
        let cpuPref = NotchWingPreference(desiredWidth: 48, compactWidth: 44, minimumWidth: 40)
        let timerPref = NotchWingPreference(desiredWidth: 72, compactWidth: 64, minimumWidth: 54)
        let normalFlank = NotchFlankLayout.solve(
            safeArea: notched, clearance: normalClearance,
            left: cpuPref, right: timerPref, heightExtra: 0, hovering: false
        )!
        precondition(normalFlank.frame.maxY == builtIn.maxY)
        precondition(normalFlank.height == notched.menuBarHeight)
        precondition(normalFlank.leftWingWidth == 48 && normalFlank.rightWingWidth == 72)
        precondition(normalFlank.cameraGapWidth == 220)
        precondition(normalFlank.frame.minX == 742 && normalFlank.frame.maxX == 1082)
        precondition(normalFlank.frame.maxX <= 1137 - MenuBarClearance.defaultSafetyGap)
        precondition(!normalFlank.leftYielded && !normalFlank.rightYielded)
        precondition(normalFlank.leadingTopFlare == 6 && normalFlank.trailingTopFlare == 6)

        // 3. Moderately crowded right status bar (status item at x=1086 -> 68pt free):
        //    Right wing degrades cleanly from full (72pt) to compact (64pt), never overlapping status icons.
        let tightRightWindows = [
            MenuBarWindowSample(windowNumber: 1, layer: 25, alpha: 1, cgBounds: CGRect(x: 1086, y: 0, width: 32, height: 39)),
        ]
        let tightRightClearance = MenuBarClearance.resolve(
            safeArea: notched, primaryScreenHeight: builtIn.height,
            windows: tightRightWindows, excludedWindowNumbers: [], leftMenuRightEdgeCG: 420
        )
        precondition(tightRightClearance.availableRight == 68)
        let tightRightFlank = NotchFlankLayout.solve(
            safeArea: notched, clearance: tightRightClearance,
            left: cpuPref, right: timerPref, heightExtra: 0, hovering: true
        )!
        precondition(tightRightFlank.rightCompact && !tightRightFlank.rightYielded)
        precondition(tightRightFlank.rightWingWidth <= 68)
        precondition(tightRightFlank.frame.maxX <= 1086 - MenuBarClearance.defaultSafetyGap)

        // 4. Heavily crowded right status bar (status item at x=1040 -> 22pt free, or x=1004 -> 0pt free):
        //    Right wing yields completely to 0pt, inset inside hardware notch; left wing keeps working!
        for crowdedX in [CGFloat(1040), CGFloat(1015), CGFloat(1004)] {
            let crowdedClearance = MenuBarClearance.resolve(
                safeArea: notched, primaryScreenHeight: builtIn.height,
                windows: [MenuBarWindowSample(windowNumber: 2, layer: 25, alpha: 1, cgBounds: CGRect(x: crowdedX, y: 0, width: 36, height: 39))],
                excludedWindowNumbers: [], leftMenuRightEdgeCG: 420
            )
            let flank = NotchFlankLayout.solve(
                safeArea: notched, clearance: crowdedClearance,
                left: cpuPref, right: timerPref
            )!
            precondition(flank.rightWingWidth == 0 && flank.rightYielded)
            precondition(flank.trailingTopFlare == 0)
            precondition(flank.frame.maxX == 1010 - NotchFlankLayout.passiveNotchInset)
            precondition(flank.frame.maxX <= crowdedX || crowdedX < 1010)
            precondition(flank.leftWingWidth == 48 && !flank.leftYielded)
            // Transient activity knows it should drop below the menu bar rather than crowd icons
            precondition(flank.shouldDropDownTransientActivity)
        }

        // 5. Crowded left app menus (AX reports menu bar reaching x=760 -> 22pt free):
        //    Left wing yields to 0pt so app menus stay 100% uncovered; right wing unaffected!
        let crowdedLeftClearance = MenuBarClearance.resolve(
            safeArea: notched, primaryScreenHeight: builtIn.height,
            windows: liveWindows, excludedWindowNumbers: [9001], leftMenuRightEdgeCG: 760
        )
        precondition(crowdedLeftClearance.availableLeft == 22)
        let crowdedLeftFlank = NotchFlankLayout.solve(
            safeArea: notched, clearance: crowdedLeftClearance,
            left: cpuPref, right: timerPref
        )!
        precondition(crowdedLeftFlank.leftWingWidth == 0 && crowdedLeftFlank.leftYielded)
        precondition(crowdedLeftFlank.leadingTopFlare == 0)
        precondition(crowdedLeftFlank.frame.minX == 790 + NotchFlankLayout.passiveNotchInset)
        precondition(crowdedLeftFlank.rightWingWidth == 72 && !crowdedLeftFlank.rightYielded)

        // 6. Music slot graceful degradation: artwork+title (106pt) -> artwork-only (46pt) -> yield (0pt).
        let musicPref = NotchWingPreference(desiredWidth: 106, compactWidth: 46, minimumWidth: 40)
        let midLeftClearance = MenuBarClearance(availableLeft: 60, availableRight: 119, leftMenuRightEdge: 722, rightStatusLeftEdge: 1137)
        let compactMusic = NotchFlankLayout.solve(
            safeArea: notched, clearance: midLeftClearance,
            left: musicPref, right: .empty
        )!
        precondition(compactMusic.leftCompact && compactMusic.leftWingWidth == 46 && !compactMusic.leftYielded)
        precondition(compactMusic.rightWingWidth == 0 && !compactMusic.rightYielded)

        // 7. Expanded workbench card ALWAYS stays strictly below menuBarBand, never covering menus or icons.
        let notchPanelSize = CGSize(width: 680, height: notched.menuBarHeight + 4 + 288 + 30)
        let notchPanel = notched.notchPanelFrame(size: notchPanelSize)
        precondition(notchPanel.maxY == builtIn.maxY && notchPanel.midX == 900)
        precondition(notchPanel.contains(normalFlank.frame))
        let expandedRect = notched.expandedWorkbenchRect(inPanel: notchPanel, size: CGSize(width: 620, height: 288), topGap: 4)
        precondition(!notched.intrudesMenuBar(expandedRect))
        precondition(expandedRect.maxY == notched.menuBarBand.minY - 4)
        precondition(expandedRect.midX == 900)
        precondition(notchPanel.contains(expandedRect))

        // Dropped-down transient activity pill also stays strictly below menuBarBand.
        let dropDown = notched.activityDropDownRect(inPanel: notchPanel, size: CGSize(width: 240, height: 30), topGap: 6)
        precondition(!notched.intrudesMenuBar(dropDown))
        precondition(dropDown.maxY == notched.menuBarBand.minY - 6)

        // 8. Auto-hidden menu bar preserves full camera + menu bar height.
        let hiddenBar = MenuBarSafeArea.resolve(
            screenFrame: builtIn, visibleFrame: builtIn, safeTopInset: 38,
            auxiliaryLeft: auxLeft, auxiliaryRight: auxRight, statusBarThickness: 22
        )
        precondition(hiddenBar.dockingFrame == notched.dockingFrame)
        precondition(hiddenBar.menuBarHeight == 39)

        // 9. External / non-notched display: no notch flanking; everything stays below menuBarBand.
        let externalScreen = CGRect(x: -1440, y: 240, width: 1440, height: 900)
        let external = MenuBarSafeArea.resolve(
            screenFrame: externalScreen, visibleFrame: externalScreen,
            safeTopInset: 0, auxiliaryLeft: nil, auxiliaryRight: nil, statusBarThickness: 0
        )
        precondition(external.notch == nil && external.menuBarHeight == 24)
        precondition(NotchFlankLayout.solve(safeArea: external, clearance: .unconstrained, left: cpuPref, right: timerPref) == nil)
        precondition(external.dockingFrame.maxY == 1116)

        // 10. All floating docks, corners, and free-drag clamping never intrude into menuBarBand.
        let workbench = CGSize(width: 620, height: 288)
        let panelSize = CGSize(width: 680, height: 318)
        let compact = CGSize(width: IslandFootprint.compactWidth(
            notchWidth: 220, hasContent: true, isPlaying: true, hovering: true), height: 30)
        let gap: CGFloat = 6
        for geometry in [notched, hiddenBar, external] {
            for dock in NotchDock.allCases {
                for anchor in NotchPlacement.Anchor.allCases {
                    let placement = NotchPlacement(dock: dock, anchor: anchor, along: 1000)
                    let frame = geometry.panelFrame(placement: placement, size: panelSize)
                    precondition(geometry.dockingFrame.contains(frame) && !geometry.intrudesMenuBar(frame))
                    for size in [compact, workbench] {
                        let island = placement.islandRect(inPanel: frame, size: size, gap: gap)
                        let hover = geometry.clippedBelowMenuBar(island.insetBy(dx: -12, dy: -12))
                        precondition(frame.contains(island))
                        precondition(hover.contains(island) && !geometry.intrudesMenuBar(hover))
                        precondition(!hover.contains(CGPoint(x: island.midX, y: geometry.menuBarBand.midY)))
                    }
                }
            }
            for origin in [geometry.menuBarBand.origin, geometry.screenFrame.origin,
                           CGPoint(x: geometry.screenFrame.maxX, y: geometry.screenFrame.maxY + 50)] {
                let dragged = geometry.panelFrame(placement: .home, size: panelSize, dragOrigin: origin)
                precondition(geometry.dockingFrame.contains(dragged) && !geometry.intrudesMenuBar(dragged))
            }
        }

        // 11. Multi-display offset coordinate check (notched display positioned to the right of an external display).
        let secondaryNotchedFrame = CGRect(x: 1920, y: 100, width: 1800, height: 1169)
        let secondaryNotched = MenuBarSafeArea.resolve(
            screenFrame: secondaryNotchedFrame,
            visibleFrame: CGRect(x: 1920, y: 183, width: 1800, height: 1047),
            safeTopInset: 38,
            auxiliaryLeft: CGRect(x: 1920, y: 1231, width: 790, height: 38),
            auxiliaryRight: CGRect(x: 2930, y: 1231, width: 790, height: 38),
            statusBarThickness: 24
        )
        // Primary display height = 1080 -> cgTop of secondary = 1080 - 1269 = -189
        let secondaryWindows = [
            // Status item on primary display (must NOT affect secondary)
            MenuBarWindowSample(windowNumber: 10, layer: 25, alpha: 1, cgBounds: CGRect(x: 1100, y: 0, width: 32, height: 39)),
            // Status item on secondary display at x=3020
            MenuBarWindowSample(windowNumber: 11, layer: 25, alpha: 1, cgBounds: CGRect(x: 3020, y: -189, width: 36, height: 39)),
        ]
        let secondaryClearance = MenuBarClearance.resolve(
            safeArea: secondaryNotched, primaryScreenHeight: 1080,
            windows: secondaryWindows, excludedWindowNumbers: [], leftMenuRightEdgeCG: 2500
        )
        precondition(secondaryClearance.rightStatusLeftEdge == 3020)
        precondition(secondaryClearance.availableRight == 82) // 3020 - 2930 - 8
        precondition(secondaryClearance.availableLeft == 202) // 2710 - 2500 - 8

        // 12. Tiny display clamping safety.
        let tiny = CGRect(x: 50, y: -220, width: 300, height: 220)
        let tinyArea = MenuBarSafeArea.resolve(
            screenFrame: tiny, visibleFrame: tiny, safeTopInset: 0,
            auxiliaryLeft: nil, auxiliaryRight: nil, statusBarThickness: 24
        )
        precondition(tinyArea.panelFrame(placement: .home, size: panelSize) == tinyArea.dockingFrame)

        print("PASS: notch-flanking layout, right status-icon avoidance, left menu-bar avoidance, compact degradation, crowded dropdown fallback, menu-bar-safe expanded workbench, multi-display and drag clamping")
    }
}
