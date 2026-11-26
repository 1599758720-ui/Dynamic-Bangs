import Combine
import SwiftUI

final class NotchViewModel: ObservableObject {
    var onOpenRequested: (() -> Void)?
    var onCloseRequested: (() -> Void)?
    var onOpenQuickActions: (() -> Void)?
    var onQuickActionSelected: ((QuickAction) -> Void)?
    @Published var showsQuickActions = false
    @Published var quickActionError: String?
    @Published var showsDashboard = true
    @Published var isHovering = false
    @Published var musicSwipe: MusicSwipe?
    @Published var isEditingWidgets = false
    @Published var isPinned = false
    @Published var panelVisible = true
    @Published var selectedWidget: DashboardWidget?
    @Published var screenGeometry: MenuBarSafeArea?
    @Published var menuBarClearance: MenuBarClearance = .unconstrained
    @Published var panelOrigin: CGPoint = .zero

    /// True when the island is anchored to the physical camera notch at the
    /// top-center home pose on a notched MacBook Pro display.
    var isNotchFlankingMode: Bool {
        placement.isHome && screenGeometry?.notch != nil
    }

    /// Raw values are the case names and are persisted (see `selectedTab`), so
    /// renaming a case silently forgets which tab the user was on — add a new
    /// case rather than renaming one.
    enum Tab: String, CaseIterable {
        case music
        case spectrum
        case files
        case capture
        case timer

        var title: String {
            switch self {
            case .music:   return String(localized: "tab.music", defaultValue: "Musik")
            case .spectrum: return String(localized: "tab.spectrum", defaultValue: "Spectrum")
            case .files:   return String(localized: "tab.files", defaultValue: "Ablage")
            case .capture: return String(localized: "tab.capture", defaultValue: "Capture")
            case .timer:   return String(localized: "tab.timer", defaultValue: "Timer")
            }
        }

        var icon: String {
            switch self {
            case .music:   return "radio.fill"
            case .spectrum: return "waveform"
            case .files:   return "tray.full"
            case .capture: return "square.and.pencil"
            case .timer:   return "timer"
            }
        }
    }

    enum IslandState {
        case expanded
        case band
        case solo
        case condensing
        case collapsed
    }

    @Published var islandState: IslandState = .collapsed {
        didSet {
            if islandState != .expanded { pagesSettled = false }
            if islandState == .collapsed { chromeRevealed = false }
        }
    }

    @Published var pagesSettled = false {
        didSet {
            guard pagesSettled != oldValue else { return }
            guard pagesSettled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchLayout.chromeRevealDelay) { [weak self] in
                guard let self, self.pagesSettled else { return }
                self.chromeRevealed = true
            }
        }
    }

    @Published private(set) var chromeRevealed = false

    var isExpanded: Bool { islandState == .expanded }
    var occupiesExpandedFootprint: Bool { islandState != .collapsed }

    @Published var selectedTab: Tab = NotchViewModel.restoredTab {
        didSet {
            guard selectedTab != oldValue else { return }
            UserDefaults.standard.set(selectedTab.rawValue, forKey: Self.selectedTabKey)
        }
    }

    private static let selectedTabKey = "selectedTab"

    @Published var placement: NotchPlacement = .home

    private static var restoredTab: Tab {
        let fallback = enabledTabs.first ?? .music
        guard let raw = UserDefaults.standard.string(forKey: selectedTabKey),
              let tab = Tab(rawValue: raw),
              UserSettings.shared.isTabEnabled(tab) else { return fallback }
        return tab
    }

    static var enabledTabs: [Tab] {
        Tab.allCases.filter { UserSettings.shared.isTabEnabled($0) }
    }

    private var cancellables: Set<AnyCancellable> = []

    init() {
        UserSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let enabled = Self.enabledTabs
                if !enabled.contains(self.selectedTab), let fallback = enabled.first {
                    self.selectedTab = fallback
                }
            }
            .store(in: &cancellables)
    }

    @Published var isInteractionLocked: Bool = false

    var holdsIslandOpen: Bool {
        islandState == .expanded && (showsQuickActions || (!showsDashboard && selectedTab == .spectrum))
    }

    @Published var captureFocusToken: Int = 0

    func requestCaptureFocus() {
        guard Self.enabledTabs.contains(.capture) else { return }
        selectedTab = .capture
        captureFocusToken += 1
    }

    // MARK: - Unified sizing and geometry

    var collapsedHeight: CGFloat { NotchLayout.currentCollapsedHeight }
    var expandedWidth: CGFloat { expandedIslandSize.width }
    var expandedHeight: CGFloat { expandedIslandSize.height }

    var expandedIslandSize: CGSize {
        guard let bounds = screenGeometry?.dockingFrame.size else {
            return CGSize(width: NotchLayout.workbenchWidth, height: NotchLayout.expandedHeight)
        }
        return CGSize(width: max(0, min(NotchLayout.workbenchWidth, bounds.width - NotchLayout.panelHorizontalMargin)),
                      height: max(0, min(NotchLayout.expandedHeight, bounds.height - NotchLayout.panelVerticalMargin)))
    }

    private func compactSize(hasAudio: Bool, activity: NotchActivity?, swipe: MusicSwipe?, timerText: String?) -> CGSize {
        let width = activity?.progress != nil
            ? NotchLayout.progressHUDWidth
            : collapsedWidth(isPlaying: hasAudio || activity != nil || swipe != nil, hasItems: false, timerText: timerText)
        return CGSize(width: min(expandedWidth, width), height: min(expandedHeight, collapsedHeight))
    }

    func collapsedWidth(isPlaying: Bool, hasItems: Bool, timerText: String?) -> CGFloat {
        IslandFootprint.compactWidth(notchWidth: screenGeometry?.notch?.width ?? 0,
                                     hasContent: hasCompactContent(hasAudio: isPlaying, timerText: timerText),
                                     isPlaying: isPlaying, hovering: isHovering && !Motion.isReduced)
    }

    func hasCompactContent(hasAudio: Bool, timerText: String?) -> Bool {
        let layout = WidgetStore.shared.layout
        return layout.leading != .none || layout.trailing != .none || hasAudio || timerText != nil
            || (layout.systemStatusEnabled && SystemStatus.shared.focusActive == true)
    }

    /// Content-fitted horizontal budgets for the left and right wings beside
    /// the physical camera housing. Tight sizing preserves maximum menu bar
    /// room even when Accessibility permission is not enabled.
    func wingPreferences(hasAudio: Bool,
                         activity: NotchActivity?,
                         swipe: MusicSwipe?,
                         timerText: String?) -> (left: NotchWingPreference, right: NotchWingPreference) {
        if swipe != nil {
            return (
                left: NotchWingPreference(desiredWidth: 42, compactWidth: 36, minimumWidth: 32),
                right: NotchWingPreference(desiredWidth: 64, compactWidth: 56, minimumWidth: 48)
            )
        }
        if let activity {
            let rightPref: NotchWingPreference
            if activity.progress != nil {
                rightPref = NotchWingPreference(desiredWidth: 96, compactWidth: 74, minimumWidth: 58)
            } else if activity.detail != nil {
                rightPref = NotchWingPreference(desiredWidth: 108, compactWidth: 78, minimumWidth: 58)
            } else {
                rightPref = NotchWingPreference(desiredWidth: 84, compactWidth: 64, minimumWidth: 50)
            }
            return (
                left: NotchWingPreference(desiredWidth: 44, compactWidth: 38, minimumWidth: 34),
                right: rightPref
            )
        }

        let layout = WidgetStore.shared.layout
        let showsFocus = layout.systemStatusEnabled && SystemStatus.shared.focusActive == true
        let focusExtra: CGFloat = showsFocus ? 16 : 0
        let showsWave = hasAudio && layout.showWave
        let waveExtra: CGFloat = showsWave ? 24 : 0

        let leftPref: NotchWingPreference = {
            switch layout.leading {
            case .none:
                return showsFocus
                    ? NotchWingPreference(desiredWidth: 36, compactWidth: 32, minimumWidth: 28)
                    : .empty
            case .system:
                return NotchWingPreference(desiredWidth: 48 + focusExtra, compactWidth: 44, minimumWidth: 40)
            case .timer:
                return NotchWingPreference(desiredWidth: 72 + focusExtra, compactWidth: 64, minimumWidth: 54)
            case .battery:
                return NotchWingPreference(desiredWidth: 68 + focusExtra, compactWidth: 60, minimumWidth: 50)
            case .music:
                return NotchWingPreference(desiredWidth: 106 + focusExtra, compactWidth: 46, minimumWidth: 40)
            }
        }()

        let rightPref: NotchWingPreference = {
            switch layout.trailing {
            case .none:
                if showsWave {
                    return NotchWingPreference(desiredWidth: 42, compactWidth: 36, minimumWidth: 32)
                }
                if timerText != nil && layout.leading != .timer {
                    return NotchWingPreference(desiredWidth: 70, compactWidth: 62, minimumWidth: 54)
                }
                return .empty
            case .system:
                return NotchWingPreference(desiredWidth: 48 + waveExtra, compactWidth: 44, minimumWidth: 40)
            case .timer:
                return NotchWingPreference(desiredWidth: 72 + waveExtra, compactWidth: 64, minimumWidth: 54)
            case .battery:
                return NotchWingPreference(desiredWidth: 68 + waveExtra, compactWidth: 60, minimumWidth: 50)
            case .music:
                return NotchWingPreference(desiredWidth: 106 + waveExtra, compactWidth: 46, minimumWidth: 40)
            }
        }()

        return (left: leftPref, right: rightPref)
    }

    func flankLayout(hasAudio: Bool,
                     activity: NotchActivity?,
                     swipe: MusicSwipe?,
                     timerText: String?) -> NotchFlankLayout? {
        guard isNotchFlankingMode, let geometry = screenGeometry else { return nil }
        let prefs = wingPreferences(hasAudio: hasAudio, activity: activity, swipe: swipe, timerText: timerText)
        return NotchFlankLayout.solve(
            safeArea: geometry,
            clearance: menuBarClearance,
            left: prefs.left,
            right: prefs.right,
            heightExtra: CGFloat(UserSettings.shared.notchHeightExtra),
            hovering: isHovering && !Motion.isReduced
        )
    }

    /// Progress HUDs drop below the notch. Other transients drop only when
    /// the available menu bar space cannot accommodate the requested wings.
    func shouldDropDownTransientActivity(hasAudio: Bool,
                                         activity: NotchActivity?,
                                         swipe: MusicSwipe?,
                                         timerText: String?) -> Bool {
        guard isNotchFlankingMode else { return false }
        return shouldDropDown(activity: activity, swipe: swipe, flank: flankLayout(
            hasAudio: hasAudio, activity: activity, swipe: swipe, timerText: timerText
        ))
    }

    private func shouldDropDown(activity: NotchActivity?, swipe: MusicSwipe?,
                                flank: @autoclosure () -> NotchFlankLayout?) -> Bool {
        if activity?.progress != nil { return true }
        guard activity != nil || swipe != nil else { return false }
        return flank()?.shouldDropDownTransientActivity == true
    }

    /// Single source of truth for the rendered and interactive island rect in
    /// screen coordinates, shared by SwiftUI layout and AppKit hit-testing.
    func activeIslandScreenRect(panelFrame: CGRect,
                                hasAudio: Bool,
                                activity: NotchActivity?,
                                swipe: MusicSwipe?,
                                timerText: String?) -> CGRect {
        guard let geometry = screenGeometry, !geometry.dockingFrame.isEmpty else { return .zero }
        if isNotchFlankingMode {
            if occupiesExpandedFootprint {
                return geometry.expandedWorkbenchRect(
                    inPanel: panelFrame, size: expandedIslandSize, topGap: NotchLayout.expandedNotchTopGap
                )
            }
            let flank = flankLayout(hasAudio: hasAudio, activity: activity, swipe: swipe, timerText: timerText)
            if shouldDropDown(activity: activity, swipe: swipe, flank: flank) {
                let pill = compactSize(hasAudio: hasAudio, activity: activity, swipe: swipe, timerText: timerText)
                return geometry.activityDropDownRect(
                    inPanel: panelFrame, size: pill, topGap: NotchLayout.islandTopGap
                )
            }
            if let flank { return flank.frame }
        }
        let size = occupiesExpandedFootprint
            ? expandedIslandSize
            : compactSize(hasAudio: hasAudio, activity: activity, swipe: swipe, timerText: timerText)
        return placement.islandRect(inPanel: panelFrame, size: size, gap: NotchLayout.islandTopGap)
    }

    func collapsedTrailingShift(isPlaying: Bool, hasItems: Bool, timerText: String?) -> CGFloat {
        0
    }

    static func timerSegmentWidth(_ text: String) -> CGFloat {
        NotchLayout.collapsedTimerIconWidth + NotchLayout.collapsedTimerInnerSpacing
            + CGFloat(text.count) * NotchLayout.collapsedTimerCharWidth
    }

    var soloWidth: CGFloat { NotchLayout.soloBaseWidth }

    var panelSize: CGSize {
        let baseWidth = expandedWidth + NotchLayout.panelHorizontalMargin
        let baseHeight = expandedHeight + NotchLayout.panelVerticalMargin
        if isNotchFlankingMode, let geometry = screenGeometry {
            return CGSize(
                width: baseWidth,
                height: geometry.menuBarHeight + NotchLayout.expandedNotchTopGap + baseHeight
            )
        }
        return CGSize(width: baseWidth, height: baseHeight)
    }
    var panelWidth: CGFloat { panelSize.width }
    var panelHeight: CGFloat { panelSize.height }
}
