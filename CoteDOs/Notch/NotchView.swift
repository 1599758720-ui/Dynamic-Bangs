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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hasSignal = false

    private var hasAudio: Bool { nowPlaying.isPlaying || hasSignal }

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
                    .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.88), value: activeFlank)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: viewModel.isHovering)
                }
            }
        }
        .clipped()
        .environment(\.colorScheme, .dark)
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
        let rimOpacity: Double = contrast == .increased
            ? 0.34
            : (viewModel.isHovering ? 0.18 : 0.08)

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
        .background {
            shape.fill(Color.black)
        }
        .clipShape(shape)
        .overlay {
            if flank.hasVisibleWings {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.clear, .white.opacity(rimOpacity)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
                .allowsHitTesting(false)
            }
        }
        .shadow(color: .black.opacity(flank.hasVisibleWings ? 0.22 : 0),
                radius: flank.hasVisibleWings ? 4 : 0, y: 1.5)
    }

    @ViewBuilder
    private func floatingChrome(expanded: Bool, size: CGSize) -> some View {
        let radius = expanded ? NotchLayout.floatingExpandedCornerRadius : size.height / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

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
            if expanded {
                if reduceTransparency {
                    Color(red: 0.08, green: 0.085, blue: 0.10)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                        .overlay {
                            LinearGradient(colors: [
                                Color(red: 0.04, green: 0.045, blue: 0.06).opacity(0.84),
                                Color(red: 0.07, green: 0.075, blue: 0.095).opacity(0.78),
                            ], startPoint: .top, endPoint: .bottom)
                        }
                        .overlay {
                            if nowPlaying.isPlaying, let color = nowPlaying.artworkColor {
                                RadialGradient(colors: [color.opacity(0.12), .clear],
                                               center: .topLeading, startRadius: 10, endRadius: 285)
                            }
                        }
                }
            } else if reduceTransparency {
                Color(white: 0.06)
            } else {
                Rectangle().fill(.regularMaterial)
                    .overlay {
                        LinearGradient(colors: [Color(white: 0.03).opacity(0.86),
                                                Color(white: 0.075).opacity(0.80)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(contrast == .increased ? 0.44 : (expanded ? 0.24 : 0.18)),
                        .white.opacity(contrast == .increased ? 0.16 : 0.08),
                        .white.opacity(contrast == .increased ? 0.10 : 0.04),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(expanded ? 0.44 : 0.28),
                radius: expanded ? 22 : 8, y: expanded ? 10 : 3)
        .shadow(color: .black.opacity(expanded ? 0.22 : 0), radius: 4, y: 2)
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
