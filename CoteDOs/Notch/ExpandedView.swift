import SwiftUI

struct ExpandedView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    @Namespace private var tabSelection
    let nowPlaying: NowPlayingManager
    let shelf: FileShelfModel
    let pomodoro: PomodoroManager
    let capture: ObsidianCapture
    let spectrum: SpectrumAnalyzer
    var activity: NotchActivity?
    var spectrumWaveDrawnByOverlay = false
    var spectrumWaveBarCount: Int?

    private var showsOverview: Bool { viewModel.showsDashboard && !viewModel.showsQuickActions }

    private enum Page: Hashable {
        case search, overview, system, tab(NotchViewModel.Tab)
    }

    private var page: Page {
        if viewModel.showsQuickActions { return .search }
        if showsOverview { return .overview }
        if viewModel.selectedWidget == .system { return .system }
        return .tab(viewModel.selectedTab)
    }

    var body: some View {
        VStack(spacing: NotchStyle.Spacing.md) {
            toolbar
            ZStack {
                VStack { pageContent }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(page)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: 5)))
            }
            .animation(reduceMotion ? nil : NotchStyle.Motion.surface, value: page)
        }
        .padding(.horizontal, NotchLayout.expandedContentInset)
        .padding(.vertical, NotchStyle.Spacing.cardPadding)
        .foregroundStyle(NotchStyle.primaryText)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .search:
            VStack(spacing: 6) {
                QuickActionsView { viewModel.onQuickActionSelected?($0) }
                if let error = viewModel.quickActionError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(NotchStyle.focusOrange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .overview:
            DashboardView(viewModel: viewModel, nowPlaying: nowPlaying, pomodoro: pomodoro, spectrum: spectrum, activity: activity)
        case .system:
            VStack(alignment: .leading, spacing: 12) {
                SystemWidgetContent()
                Button("调整缩略显示…") { WidgetPreferencesWindow.shared.show() }
                    .buttonStyle(NotchButtonStyle())
            }
            .frame(maxWidth: 230)
        case let .tab(tab):
            switch tab {
            case .timer: PomodoroView(pomodoro: pomodoro)
            case .files: ShelfView(shelf: shelf)
            case .capture: CaptureView(capture: capture, viewModel: viewModel)
            case .spectrum: SpectrumStageView(levels: spectrum.bands, isLive: spectrum.isLive,
                isActive: nowPlaying.screensAwake, tint: scheme == .dark ? .white : .black)
            case .music: NowPlayingView(nowPlaying: nowPlaying, spectrum: spectrum)
            }
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) { header }
        } else {
            header
        }
    }

    private enum TabPresentation {
        case symbols, titles, scrolling
    }

    private var header: some View {
        HStack(spacing: NotchStyle.Spacing.md) {
            if viewModel.showsQuickActions {
                iconButton("返回工作台", symbol: "chevron.left") { viewModel.onOpenRequested?() }
                Text("快速搜索")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            } else {
                ViewThatFits(in: .horizontal) {
                    segments(.symbols).fixedSize()
                    segments(.titles).fixedSize()
                    ScrollView(.horizontal) {
                        segments(.scrolling)
                    }
                    .scrollIndicators(.hidden)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
            if !viewModel.showsQuickActions {
                Button {
                    viewModel.onOpenQuickActions?()
                } label: {
                    HStack(spacing: 5) {
                        Label("搜索", systemImage: "magnifyingglass")
                        Text("⌥⌘K")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(NotchStyle.secondary)
                            .accessibilityHidden(true)
                    }
                    .fixedSize()
                }
                .buttonStyle(NotchButtonStyle(usesGlass: true))
                .help("快速搜索 · ⌥⌘K")
                if showsOverview {
                    iconButton(viewModel.isEditingWidgets ? "完成编辑" : "编辑组件",
                               symbol: viewModel.isEditingWidgets ? "checkmark" : "slider.horizontal.3",
                               active: viewModel.isEditingWidgets) {
                        withAnimation(reduceMotion ? nil : NotchStyle.Motion.layout) {
                            viewModel.isEditingWidgets.toggle()
                        }
                    }
                    .accessibilityAddTraits(viewModel.isEditingWidgets ? .isSelected : [])
                }
                iconButton(viewModel.isPinned ? "取消固定展开" : "固定展开",
                           symbol: viewModel.isPinned ? "pin.fill" : "pin",
                           active: viewModel.isPinned) {
                    viewModel.isPinned.toggle()
                }
                .accessibilityAddTraits(viewModel.isPinned ? .isSelected : [])
            }
            iconButton("收起", symbol: "xmark") { viewModel.onCloseRequested?() }
                .help("收起 · Escape")
        }
        .font(NotchStyle.Typography.control)
        .padding(.horizontal, NotchStyle.Spacing.sm)
        .frame(height: 36)
        .animation(reduceMotion ? nil : NotchStyle.Motion.surface, value: page)
    }

    private func segments(_ presentation: TabPresentation) -> some View {
        HStack(spacing: 2) {
            segment("总览", symbol: "square.grid.2x2.fill", selected: showsOverview, presentation: presentation) {
                viewModel.onOpenRequested?()
            }
            tab(.music, title: "音乐", symbol: "music.note", presentation: presentation)
            tab(.timer, title: "番茄", symbol: "timer", presentation: presentation)
            tab(.capture, title: "速记", symbol: "square.and.pencil", presentation: presentation)
            tab(.files, title: "暂存", symbol: "tray.full", presentation: presentation)
            tab(.spectrum, title: "频谱", symbol: "waveform", presentation: presentation)
        }
        .padding(3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工作台导航")
    }

    @ViewBuilder
    private func tab(_ tab: NotchViewModel.Tab, title: String, symbol: String, presentation: TabPresentation) -> some View {
        if settings.isTabEnabled(tab) {
            segment(title, symbol: symbol,
                    selected: !showsOverview && viewModel.selectedWidget != .system && viewModel.selectedTab == tab,
                    presentation: presentation) {
                viewModel.selectedWidget = nil
                viewModel.selectedTab = tab
                viewModel.isEditingWidgets = false
                viewModel.isInteractionLocked = false
                viewModel.showsDashboard = false
            }
        }
    }

    private func segment(_ title: String, symbol: String, selected: Bool, presentation: TabPresentation,
                         action: @escaping () -> Void) -> some View {
        let showsSymbol = presentation == .symbols
        return Button(action: action) {
            if showsSymbol {
                Label(title, systemImage: symbol)
            } else {
                Text(title)
            }
        }
        .buttonStyle(NotchButtonStyle(tint: selected || contrast == .increased ? NotchStyle.primaryText : NotchStyle.secondary,
                                    horizontalPadding: showsSymbol ? 9 : 5))
        .background {
            if selected {
                NotchTabIndicator()
                    .matchedGeometryEffect(id: presentation, in: tabSelection)
                    .transition(.identity)
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func iconButton(_ title: String, symbol: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(NotchButtonStyle(shape: .circle(28), selected: active, usesGlass: true))
            .animation(reduceMotion ? nil : NotchStyle.Motion.layout, value: active)
            .help(title)
    }
}
