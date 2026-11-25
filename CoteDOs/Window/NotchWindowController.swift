import AppKit
import Combine
import SwiftUI

final class NotchWindowController {
    private let panel: NotchPanel
    private let container: NotchContainerView
    private let viewModel: NotchViewModel
    private let nowPlaying: NowPlayingManager
    private let shelf: FileShelfModel
    private let activities: ActivityManager
    private let pomodoro: PomodoroManager
    private let spectrum: SpectrumAnalyzer
    private let menuBarMonitor = MenuBarOverlapMonitor()

    var onOpenSettings: (() -> Void)?
    var onPauseChanged: ((Bool) -> Void)?

    private var lockPanel: NotchPanel?
    private var isSuspended = false
    private var policy = PanelPresencePolicy()
    private var cancellables: Set<AnyCancellable> = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var collapseWorkItem: DispatchWorkItem?
    private var expandedInteraction = ExpandedInteraction()
    private var musicSwipeRecognizer = MusicSwipeRecognizer()
    private var musicFeedbackWork: DispatchWorkItem?
    private var pendingAppLaunch: UUID?

    init(viewModel: NotchViewModel, nowPlaying: NowPlayingManager, shelf: FileShelfModel,
         activities: ActivityManager, pomodoro: PomodoroManager, capture: ObsidianCapture, spectrum: SpectrumAnalyzer) {
        self.viewModel = viewModel
        self.nowPlaying = nowPlaying
        self.shelf = shelf
        self.activities = activities
        self.pomodoro = pomodoro
        self.spectrum = spectrum

        let frame = NSRect(origin: .zero, size: viewModel.panelSize)
        panel = NotchPanel(contentRect: frame)
        container = NotchContainerView(frame: frame)

        let hostingView = NSHostingView(rootView: NotchRootView(
            viewModel: viewModel, nowPlaying: nowPlaying, shelf: shelf, activities: activities,
            pomodoro: pomodoro, capture: capture, spectrum: spectrum
        ))
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container

        container.islandRect = { [weak self] in
            guard let self else { return .zero }
            return self.localRect(self.pointerHitRect)
        }
        container.dropRect = { [weak self] in
            guard let self else { return .zero }
            return self.localRect(self.dropRect)
        }
        container.onDragEntered = { [weak self] in self?.handleDragEntered() ?? false }
        container.onDragExited = { [weak self] in self?.handleDragExited() }
        container.onDrop = { [weak self] urls in self?.handleDrop(urls) }
        viewModel.onOpenRequested = { [weak self] in self?.presentDashboard() }
        viewModel.onCloseRequested = { [weak self] in self?.setExpanded(false) }
        viewModel.onOpenQuickActions = { [weak self] in self?.presentQuickActions() }
        viewModel.onQuickActionSelected = { [weak self] action in self?.runQuickAction(action) }

        menuBarMonitor.targetGeometryProvider = { [weak self] in
            self?.viewModel.screenGeometry
        }
        menuBarMonitor.excludedWindowNumbersProvider = { [weak self] in
            guard let self else { return [] }
            let numbers = [self.panel.windowNumber, self.lockPanel?.windowNumber].compactMap { $0 }.filter { $0 > 0 }
            return Set(numbers)
        }
        menuBarMonitor.onChange = { [weak self] clearance in
            guard let self else { return }
            self.viewModel.menuBarClearance = clearance
            self.refreshPresence(animated: false)
        }

        let contentChanged: [AnyPublisher<Void, Never>] = [
            nowPlaying.$isPlaying.map { _ in }.eraseToAnyPublisher(),
            spectrum.$hasSignal.map { _ in }.eraseToAnyPublisher(),
            pomodoro.$pillText.map { _ in }.eraseToAnyPublisher(),
            activities.$current.map { _ in }.eraseToAnyPublisher(),
            shelf.$isDropTargeted.map { _ in }.eraseToAnyPublisher(),
            viewModel.$musicSwipe.map { _ in }.eraseToAnyPublisher(),
            WidgetStore.shared.$layout.map { _ in }.eraseToAnyPublisher(),
            SystemStatus.shared.$focusActive.map { _ in }.eraseToAnyPublisher(),
            UserSettings.shared.objectWillChange.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(contentChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshPresence() }
            .store(in: &cancellables)

        SystemStatus.shared.$isLocked.removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] locked in self?.updateLockState(locked) }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)

        SpectrumFullscreen.shared.$isCollapsing.removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.setExpanded(false) }
            .store(in: &cancellables)
    }

    deinit {
        removeMonitors()
        menuBarMonitor.stop()
    }

    func show() {
        installMonitors()
        reposition()
        menuBarMonitor.start()
    }

    // MARK: - Display and visibility

    /// Refresh the hardware notch and menu bar geometry on the target display.
    func reposition() {
        if !viewModel.placement.isHome { viewModel.placement = .home }
        guard let screen = ScreenManager.targetScreen() else {
            viewModel.screenGeometry = nil
            panel.orderOut(nil)
            lockPanel?.orderOut(nil)
            return
        }
        position(on: screen)
        menuBarMonitor.refreshNow()
        if SystemStatus.shared.isLocked {
            panel.orderOut(nil)
            showLockBadge()
        } else {
            refreshPresence(animated: false)
            if !isSuspended, !panel.isVisible { panel.orderFrontRegardless() }
        }
    }

    private func position(on screen: NSScreen) {
        let geometry = ScreenManager.safeArea(for: screen)
        if viewModel.screenGeometry != geometry { viewModel.screenGeometry = geometry }

        let targetLevel: NSWindow.Level = viewModel.isNotchFlankingMode ? .statusBar : .floating
        if panel.level != targetLevel { panel.level = targetLevel }

        let frame: CGRect
        if viewModel.isNotchFlankingMode {
            frame = geometry.notchPanelFrame(size: viewModel.panelSize)
        } else {
            frame = geometry.panelFrame(placement: .home, size: viewModel.panelSize)
        }
        if viewModel.panelOrigin != frame.origin { viewModel.panelOrigin = frame.origin }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    var isPlacedByUser: Bool { false }

    func resetPlacement() {
        reposition()
    }

    var isUserDisabled: Bool { policy.hideReasons.contains(.userDisabled) }

    func setUserDisabled(_ disabled: Bool) {
        guard isUserDisabled != disabled else { return }
        if disabled {
            policy.hideReasons.insert(.userDisabled)
            shelf.isDropTargeted = false
            setExpanded(false, animated: false)
        } else {
            policy.hideReasons.remove(.userDisabled)
            reposition()
        }
        refreshPresence(animated: false)
        if SystemStatus.shared.isLocked { showLockBadge() }
        onPauseChanged?(disabled)
    }

    private var desktopAvailable: Bool {
        !isSuspended && !SystemStatus.shared.isLocked && !isUserDisabled
            && viewModel.screenGeometry?.dockingFrame.isEmpty == false
    }

    private var hasAudio: Bool { nowPlaying.isPlaying || spectrum.hasSignal }
    private var hasTransientActivity: Bool { activities.current != nil || viewModel.musicSwipe != nil }

    private func refreshPresence(animated: Bool = true) {
        let cursor = NSEvent.mouseLocation
        // In notch-flanking mode, stay mounted over the hardware notch so
        // double-click and right-click remain available even when wings yield
        // or slots are empty. Only floating mode hides completely when idle.
        let idle = !viewModel.isNotchFlankingMode
            && !viewModel.occupiesExpandedFootprint && !shelf.isDropTargeted
            && !hasTransientActivity && !viewModel.hasCompactContent(hasAudio: hasAudio, timerText: pomodoro.pillText)
            && !expandedHoverRect.contains(cursor)
        if idle { policy.hideReasons.insert(.idle) }
        else { policy.hideReasons.remove(.idle) }

        let visible = desktopAvailable && !policy.isHidden
        if viewModel.panelVisible != visible { viewModel.panelVisible = visible }
        let alpha: CGFloat = visible ? 1 : 0
        if panel.alphaValue != alpha {
            if animated && !Motion.isReduced {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = NotchLayout.idleHideFadeDuration
                    panel.animator().alphaValue = alpha
                }
            } else {
                panel.alphaValue = alpha
            }
        }
        updateClickThrough()
    }

    private func updateLockState(_ locked: Bool) {
        if locked {
            // Order the desktop window out before touching its SwiftUI content.
            panel.orderOut(nil)
            setExpanded(false, animated: false)
            musicSwipeRecognizer.reset()
            musicFeedbackWork?.cancel()
            viewModel.musicSwipe = nil
            shelf.isDropTargeted = false
            spectrum.stop()
            refreshPresence(animated: false)
            showLockBadge()
        } else {
            lockPanel?.orderOut(nil)
            reposition()
        }
    }

    /// A separate window contains only a static label. The workbench never
    /// moves to the lock screen's level or exposes its hosted view there.
    private func showLockBadge() {
        guard !isSuspended, !isUserDisabled, let geometry = viewModel.screenGeometry else {
            lockPanel?.orderOut(nil)
            return
        }
        let badgeSize = CGSize(width: 112, height: 32)
        let badgeFrame = geometry.panelFrame(placement: .home, size: badgeSize)
        let frame = geometry.clippedBelowMenuBar(badgeFrame.offsetBy(dx: 0, dy: -NotchLayout.islandTopGap))
        guard !frame.isEmpty else { lockPanel?.orderOut(nil); return }
        let badge: NotchPanel
        if let lockPanel {
            badge = lockPanel
        } else {
            badge = NotchPanel(contentRect: frame)
            badge.ignoresMouseEvents = true
            badge.canBecomeVisibleWithoutLogin = true
            badge.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
            badge.sharingType = .none
            badge.contentView = NSHostingView(rootView: LockedNotchBadge())
            lockPanel = badge
        }
        badge.setFrame(frame, display: true)
        badge.orderFrontRegardless()
    }

    func suspendMonitors() {
        guard !isSuspended else { return }
        isSuspended = true
        removeMonitors()
        menuBarMonitor.stop()
        panel.orderOut(nil)
        lockPanel?.orderOut(nil)
        shelf.isDropTargeted = false
        setExpanded(false, animated: false)
    }

    func resumeMonitors() {
        guard isSuspended else { return }
        isSuspended = false
        installMonitors()
        reposition()
        menuBarMonitor.start()
    }

    // MARK: - Shared geometry and input

    private var interactiveRect: CGRect {
        viewModel.activeIslandScreenRect(
            panelFrame: panel.frame,
            hasAudio: hasAudio,
            activity: activities.current,
            swipe: viewModel.musicSwipe,
            timerText: pomodoro.pillText
        )
    }

    private var compactHoverRect: CGRect {
        guard let geometry = viewModel.screenGeometry else { return .zero }
        let rect = interactiveRect
        guard !rect.isEmpty else { return .zero }
        let droppingDown = viewModel.shouldDropDownTransientActivity(
            hasAudio: hasAudio, activity: activities.current,
            swipe: viewModel.musicSwipe, timerText: pomodoro.pillText
        )
        if viewModel.isNotchFlankingMode && !viewModel.occupiesExpandedFootprint && !droppingDown {
            // Extend vertically up to the screen edge and slightly down, never
            // horizontally into adjacent app menus or status bar icons.
            let topBleed = max(0, geometry.screenFrame.maxY - rect.maxY) + NotchLayout.hoverTopBleed
            let bottomPad = NotchLayout.collapsedHoverInset
            return CGRect(x: rect.minX, y: rect.minY - bottomPad,
                          width: rect.width, height: rect.height + bottomPad + topBleed)
        }
        return geometry.clippedBelowMenuBar(
            rect.insetBy(dx: -NotchLayout.collapsedHoverInset, dy: -NotchLayout.collapsedHoverInset)
        )
    }

    private var pointerHitRect: CGRect {
        viewModel.occupiesExpandedFootprint ? interactiveRect : compactHoverRect
    }

    private var expandedHoverRect: CGRect {
        guard let geometry = viewModel.screenGeometry, !geometry.dockingFrame.isEmpty else { return .zero }
        let expanded: CGRect
        if viewModel.isNotchFlankingMode {
            expanded = geometry.expandedWorkbenchRect(
                inPanel: panel.frame, size: viewModel.expandedIslandSize, topGap: NotchLayout.expandedNotchTopGap
            )
        } else {
            expanded = viewModel.placement.islandRect(
                inPanel: panel.frame, size: viewModel.expandedIslandSize, gap: NotchLayout.islandTopGap
            )
        }
        return geometry.clippedBelowMenuBar(
            expanded.insetBy(dx: -NotchLayout.expandedHoverInset, dy: -NotchLayout.expandedHoverInset)
        )
    }

    private var dropRect: CGRect {
        guard desktopAvailable, let geometry = viewModel.screenGeometry else { return .zero }
        if policy.hideReasons == [.idle] {
            return geometry.clippedBelowMenuBar(
                viewModel.placement.islandRect(
                    inPanel: panel.frame, size: viewModel.expandedIslandSize, gap: NotchLayout.islandTopGap
                )
            )
        }
        return interactiveRect
    }

    private func localRect(_ rect: CGRect) -> CGRect {
        guard !rect.isEmpty else { return .zero }
        return container.convert(panel.convertFromScreen(rect), from: nil)
    }

    private func updateClickThrough(isFileDrag: Bool = false) {
        guard desktopAvailable else { panel.ignoresMouseEvents = true; return }
        let cursor = NSEvent.mouseLocation
        if isFileDrag && viewModel.isExpanded && viewModel.isEditingWidgets {
            panel.ignoresMouseEvents = false
        } else if isFileDrag && dropRect.contains(cursor) {
            panel.ignoresMouseEvents = false
        } else {
            panel.ignoresMouseEvents = policy.ignoresMouseEvents(
                cursorInsideInteractiveRect: pointerHitRect.contains(cursor), hotkeyOverride: false
            )
        }
    }

    private func installMonitors() {
        guard localMonitor == nil, globalMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .scrollWheel, .keyDown,
        ]) { [weak self] event in
            guard let self else { return event }
            if event.window === self.panel {
                if event.type == .keyDown, event.keyCode == 53, self.viewModel.isExpanded {
                    // Let the system text input method cancel marked text first.
                    if (self.panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
                    if self.viewModel.isEditingWidgets { self.viewModel.isEditingWidgets = false }
                    else { self.setExpanded(false) }
                    return nil
                }
                if event.type == .scrollWheel, self.handleMusicScroll(event) { return nil }
            }
            return self.handlePointer(event, local: true) ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp,
        ]) { [weak self] event in
            _ = self?.handlePointer(event, local: false)
        }
    }

    private func removeMonitors() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
    }

    /// Returns true only for local events owned by the compact island's press.
    private func handlePointer(_ event: NSEvent, local: Bool) -> Bool {
        guard desktopAvailable else { return false }
        switch event.type {
        case .mouseMoved:
            evaluateHover()
        case .leftMouseDown:
            let ownEvent = local && event.window === panel
            if viewModel.isExpanded {
                // A SwiftUI Menu opens its own higher-level window.
                if local, let window = event.window, window !== panel, window.level > panel.level { return false }
                if expandedInteraction.dismissesOnClick(inside: ownEvent, pinned: viewModel.isPinned,
                                                        editing: viewModel.isEditingWidgets) {
                    setExpanded(false)
                }
            } else if ownEvent, compactHoverRect.contains(panel.convertPoint(toScreen: event.locationInWindow)) {
                if event.clickCount >= 2 { presentDashboard() }
                return true
            }
        case .leftMouseDragged:
            updateClickThrough(isFileDrag: true)
        case .leftMouseUp:
            evaluateHover()
        default:
            break
        }
        return false
    }

    private var preventsHoverCollapse: Bool {
        shelf.isDropTargeted || viewModel.isEditingWidgets || viewModel.isPinned
            || viewModel.isInteractionLocked || viewModel.holdsIslandOpen
    }

    private func evaluateHover() {
        let cursor = NSEvent.mouseLocation
        if viewModel.isExpanded {
            let shouldCollapse = expandedInteraction.updatePointer(
                inside: expandedHoverRect.contains(cursor), heldOpen: preventsHoverCollapse
            )
            if !shouldCollapse {
                cancelScheduledCollapse()
            } else if collapseWorkItem == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.collapseWorkItem = nil
                    guard self.viewModel.isExpanded, self.expandedInteraction.updatePointer(
                        inside: self.expandedHoverRect.contains(NSEvent.mouseLocation),
                        heldOpen: self.preventsHoverCollapse
                    ) else { return }
                    self.setExpanded(false)
                }
                collapseWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + NotchLayout.collapseDelay, execute: work)
            }
        } else {
            let hovering = compactHoverRect.contains(cursor)
            if viewModel.isHovering != hovering { viewModel.isHovering = hovering }
        }
        refreshPresence(animated: false)
    }

    private func cancelScheduledCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    // MARK: - File drops

    private func handleDragEntered() -> Bool {
        guard desktopAvailable else { return false }
        cancelScheduledCollapse()
        shelf.isDropTargeted = true
        showPage(.files)
        setExpanded(true)
        return true
    }

    private func handleDragExited() {
        shelf.isDropTargeted = false
        evaluateHover()
    }

    private func handleDrop(_ urls: [URL]) {
        shelf.isDropTargeted = false
        guard desktopAvailable else { return }
        showPage(.files)
        urls.forEach(shelf.add)
        Haptics.perform(.generic)
        activities.fileReceived(count: urls.count)
    }

    // MARK: - Workbench routes

    func presentDashboard(editing: Bool = false) {
        guard preparePresentation(resumeIfPaused: true) else { return }
        showDashboard()
        viewModel.isEditingWidgets = editing
        showKeyPanel()
    }

    func presentTimer() {
        guard preparePresentation(resumeIfPaused: true) else { return }
        showPage(.timer, widget: .timer)
        showKeyPanel()
    }

    func presentCapture() {
        guard preparePresentation(resumeIfPaused: false) else { return }
        showPage(.capture)
        showKeyPanel()
        viewModel.requestCaptureFocus()
    }

    func presentQuickActions() {
        guard preparePresentation(resumeIfPaused: true) else { return }
        viewModel.isEditingWidgets = false
        viewModel.isInteractionLocked = false
        viewModel.quickActionError = nil
        viewModel.showsQuickActions = true
        showKeyPanel()
    }

    private func preparePresentation(resumeIfPaused: Bool) -> Bool {
        guard !SystemStatus.shared.isLocked, !isSuspended,
              !SpectrumFullscreen.shared.isPresented else { return false }
        if resumeIfPaused, isUserDisabled { setUserDisabled(false) }
        return desktopAvailable
    }

    private func showKeyPanel() {
        expandedInteraction = ExpandedInteraction(awaitingPointerEntry: true)
        setExpanded(true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func showDashboard() {
        closeQuickActions()
        viewModel.selectedWidget = nil
        viewModel.showsDashboard = true
    }

    private func showPage(_ tab: NotchViewModel.Tab, widget: DashboardWidget? = nil) {
        closeQuickActions()
        viewModel.isEditingWidgets = false
        viewModel.selectedWidget = widget
        viewModel.selectedTab = tab
        viewModel.showsDashboard = false
    }

    private func closeQuickActions() {
        pendingAppLaunch = nil
        viewModel.quickActionError = nil
        viewModel.showsQuickActions = false
    }

    private func runQuickAction(_ action: QuickAction) {
        guard desktopAvailable, viewModel.showsQuickActions else { return }
        switch action {
        case .dashboard: showDashboard()
        case .music: showPage(.music, widget: .music)
        case .spectrum: showPage(.spectrum)
        case .timer: showPage(.timer, widget: .timer)
        case .files: showPage(.files)
        case .capture: presentCapture()
        case .tasks:
            setExpanded(false)
            DailyTasksWindow.shared.show()
        case .widgets:
            setExpanded(false)
            WidgetPreferencesWindow.shared.show()
        case .settings:
            setExpanded(false)
            onOpenSettings?()
        case let .app(url):
            openApplication(url)
        }
    }

    private func openApplication(_ url: URL) {
        guard pendingAppLaunch == nil, url.isFileURL, url.pathExtension.lowercased() == "app" else { return }
        let launchMessage = "无法打开该应用。请检查应用是否仍在原位置。"
        guard FileManager.default.fileExists(atPath: url.path) else {
            viewModel.quickActionError = launchMessage
            return
        }
        let token = UUID()
        pendingAppLaunch = token
        viewModel.quickActionError = nil
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.pendingAppLaunch == token, self.desktopAvailable else { return }
                self.pendingAppLaunch = nil
                if error != nil {
                    self.viewModel.quickActionError = launchMessage
                    self.panel.makeKeyAndOrderFront(nil)
                } else {
                    self.setExpanded(false)
                }
            }
        }
    }

    private func setExpanded(_ expanded: Bool, animated: Bool = true) {
        cancelScheduledCollapse()
        if viewModel.isHovering { viewModel.isHovering = false }
        if !expanded {
            expandedInteraction = ExpandedInteraction()
            viewModel.isPinned = false
            viewModel.isEditingWidgets = false
            viewModel.isInteractionLocked = false
            closeQuickActions()
        }
        let target: NotchViewModel.IslandState = expanded ? .expanded : .collapsed
        if viewModel.islandState != target {
            let animation: Animation? = animated && !Motion.isReduced ? .spring(response: 0.26, dampingFraction: 0.88) : nil
            withAnimation(animation) { viewModel.islandState = target }
        }
        if expanded { viewModel.pagesSettled = true }
        panel.allowsKeyboardFocus = expanded
        refreshPresence(animated: animated)
        if !expanded && panel.isKeyWindow {
            panel.orderOut(nil)
            if desktopAvailable { panel.orderFrontRegardless() }
        }
    }

    // MARK: - Track changes

    private func handleMusicScroll(_ event: NSEvent) -> Bool {
        guard desktopAvailable, !policy.isHidden, WidgetStore.shared.layout.swipeTracks,
              nowPlaying.track != nil, !viewModel.isEditingWidgets, !viewModel.showsQuickActions,
              (viewModel.isExpanded ? expandedHoverRect : compactHoverRect).contains(panel.convertPoint(toScreen: event.locationInWindow)),
              !viewModel.isExpanded || (!viewModel.showsDashboard && viewModel.selectedTab == .music) else { return false }
        let direction = event.isDirectionInvertedFromDevice ? 1.0 : -1.0
        let dx = Double(event.scrollingDeltaX) * direction
        let dy = Double(event.scrollingDeltaY) * direction
        let horizontal = abs(dx) > abs(dy) * 1.2
        let swipe = musicSwipeRecognizer.consume(dx: dx, dy: dy, time: event.timestamp,
            precise: event.hasPreciseScrollingDeltas, began: event.phase.contains(.began),
            ended: event.phase.contains(.ended) || event.phase.contains(.cancelled), momentum: !event.momentumPhase.isEmpty)
        if let swipe {
            if swipe == .next { nowPlaying.nextTrack() } else { nowPlaying.previousTrack() }
            withAnimation(Motion.isReduced ? nil : .easeOut(duration: 0.15)) { viewModel.musicSwipe = swipe }
            musicFeedbackWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                withAnimation(Motion.isReduced ? nil : .easeOut(duration: 0.18)) { self?.viewModel.musicSwipe = nil }
            }
            musicFeedbackWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
        }
        return horizontal
    }
}

private struct LockedNotchBadge: View {
    var body: some View {
        Label("已锁定", systemImage: "lock.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
            .accessibilityLabel("Mac 已锁定")
    }
}
