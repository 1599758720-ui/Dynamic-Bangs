import SwiftUI
import Combine

/// The panel observes layout and activity state. Spectrum bands stay in the
/// views that draw them.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingManager
    let shelf: FileShelfModel
    @ObservedObject var activities: ActivityManager
    @ObservedObject var pomodoro: PomodoroManager
    let capture: ObsidianCapture
    let spectrum: SpectrumAnalyzer
    @ObservedObject private var widgets = WidgetStore.shared
    @ObservedObject private var settings = UserSettings.shared
    @ObservedObject private var fullscreen = SpectrumFullscreen.shared
    @ObservedObject private var systemStatus = SystemStatus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var systemScheme
    @State private var hasSignal = false

    private var hasAudio: Bool { nowPlaying.isPlaying || hasSignal }

    private var workbenchScheme: ColorScheme {
        switch settings.appearance {
        case .system: return systemScheme
        case .dark: return .dark
        case .light: return .light
        }
    }

    var body: some View {
        GeometryReader { geometry in
            if !systemStatus.isLocked {
                let expanded = viewModel.occupiesExpandedFootprint
                let panelFrame = CGRect(origin: viewModel.panelOrigin, size: geometry.size)
                let flank = expanded ? nil : viewModel.flankLayout(
                    hasAudio: hasAudio,
                    activity: activities.current,
                    swipe: viewModel.musicSwipe,
                    timerText: pomodoro.pillText
                )
                let droppingDown = !expanded && viewModel.shouldDropDownTransientActivity(
                    hasAudio: hasAudio,
                    activity: activities.current,
                    swipe: viewModel.musicSwipe,
                    timerText: pomodoro.pillText
                )
                let activeFlank: NotchFlankLayout? = droppingDown ? nil : flank
                let screenRect = viewModel.activeIslandScreenRect(
                    panelFrame: panelFrame,
                    hasAudio: hasAudio,
                    activity: activities.current,
                    swipe: viewModel.musicSwipe,
                    timerText: pomodoro.pillText
                )

                if !screenRect.isEmpty {
                    let localMidX = screenRect.midX - panelFrame.minX
                    let localMidY = geometry.size.height - (screenRect.midY - panelFrame.minY)

                    Group {
                        if let activeFlank {
                            flankChrome(flank: activeFlank, size: screenRect.size)
                                .transition(reduceMotion ? .identity : .opacity)
                        } else {
                            floatingChrome(expanded: expanded, size: screenRect.size)
                                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    }
                    .position(x: localMidX, y: localMidY)
                    .animation(reduceMotion ? nil : NotchStyle.Motion.interactive, value: activeFlank)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: viewModel.isHovering)
                }
            }
        }
        .clipped()
        .onAppear { syncServices() }
        .onReceive(spectrum.$hasSignal.removeDuplicates()) { hasSignal = $0 }
        .onChange(of: nowPlaying.isPlaying) { _, playing in
            syncServices()
            if playing { spectrum.pokeResume() }
        }
        .onChange(of: nowPlaying.screensAwake) { _, _ in syncServices() }
        .onChange(of: viewModel.islandState) { _, _ in syncServices() }
        .onChange(of: viewModel.panelVisible) { _, _ in syncServices() }
        .onChange(of: widgets.layout) { _, _ in syncServices() }
        .onChange(of: viewModel.selectedWidget) { _, _ in syncServices() }
        .onChange(of: viewModel.showsDashboard) { _, _ in syncServices() }
        .onChange(of: viewModel.showsQuickActions) { _, _ in syncServices() }
        .onChange(of: fullscreen.isPresented) { _, _ in syncServices() }
        .onChange(of: systemStatus.isLocked) { _, _ in syncServices() }
    }

    @ViewBuilder
    private func flankChrome(flank: NotchFlankLayout, size: CGSize) -> some View {
        let shape = NotchEarShape(
            bottomRadius: NotchLayout.notchFlankBottomCornerRadius,
            leadingTopFlare: flank.leadingTopFlare,
            trailingTopFlare: flank.trailingTopFlare
        )
        CollapsedView(
            viewModel: viewModel,
            nowPlaying: nowPlaying,
            pomodoro: pomodoro,
            spectrum: spectrum,
            hasAudio: hasAudio,
            activity: activities.current,
            flankLayout: flank
        )
        .frame(width: size.width, height: size.height)
        .background(shape.fill(.black))
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func floatingChrome(expanded: Bool, size: CGSize) -> some View {
        let radius = expanded ? NotchStyle.Radius.panel : NotchStyle.Radius.capsule(height: size.height)
        let shape = RoundedRectangle(cornerRadius: radius)

        Group {
            if expanded {
                ExpandedView(
                    viewModel: viewModel,
                    nowPlaying: nowPlaying,
                    shelf: shelf,
                    pomodoro: pomodoro,
                    capture: capture,
                    spectrum: spectrum,
                    activity: activities.current
                )
            } else {
                CollapsedView(
                    viewModel: viewModel,
                    nowPlaying: nowPlaying,
                    pomodoro: pomodoro,
                    spectrum: spectrum,
                    hasAudio: hasAudio,
                    activity: activities.current,
                    flankLayout: nil
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .background {
            if expanded || activities.current?.progress != nil {
                NotchFloatingMaterial(silhouette: shape, glassOpacity: expanded ? 0.42 : 0.50)
            } else {
                shape.fill(.black)
            }
        }
        .clipShape(shape)
        .overlay {
            if !expanded, activities.current?.progress == nil, contrast == .increased {
                shape.strokeBorder(.white.opacity(NotchStyle.Opacity.highContrastHairline),
                                   lineWidth: NotchStyle.hairlineWidth)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, expanded ? workbenchScheme : .dark)
    }

    private func syncServices() {
        let layout = widgets.layout
        let visible = nowPlaying.screensAwake && viewModel.panelVisible && !fullscreen.isPresented && !systemStatus.isLocked
        let showingWidgets = viewModel.isExpanded && !viewModel.showsQuickActions
        let system = visible && (layout.leading == .system || layout.trailing == .system
            || (showingWidgets && ((viewModel.showsDashboard && layout.widgets.contains(.system))
                || viewModel.selectedWidget == .system)))
        let battery = visible && (system || layout.leading == .battery || layout.trailing == .battery)
        SystemMetrics.shared.setDemand(system: system, battery: battery)
        if nowPlaying.screensAwake && !systemStatus.isLocked { spectrum.start() } else { spectrum.stop() }
    }
}
