import SwiftUI

struct ExpandedView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let nowPlaying: NowPlayingManager
    let shelf: FileShelfModel
    let pomodoro: PomodoroManager
    let capture: ObsidianCapture
    let spectrum: SpectrumAnalyzer
    var activity: NotchActivity?
    var spectrumWaveDrawnByOverlay = false
    var spectrumWaveBarCount: Int?

    private var showsOverview: Bool { viewModel.showsDashboard && !viewModel.showsQuickActions }

    var body: some View {
        VStack(spacing: 10) {
            header
            if viewModel.showsQuickActions {
                VStack(spacing: 6) {
                    QuickActionsView { viewModel.onQuickActionSelected?($0) }
                    if let error = viewModel.quickActionError {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if showsOverview {
                DashboardView(viewModel: viewModel, nowPlaying: nowPlaying, pomodoro: pomodoro, spectrum: spectrum, activity: activity)
            } else if viewModel.selectedWidget == .system {
                VStack(alignment: .leading, spacing: 12) {
                    SystemWidgetContent()
                    Button("调整缩略显示…") { WidgetPreferencesWindow.shared.show() }
                }
                .frame(maxWidth: 230)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewModel.selectedTab {
                case .timer: PomodoroView(pomodoro: pomodoro)
                case .files: ShelfView(shelf: shelf)
                case .capture: CaptureView(capture: capture, viewModel: viewModel)
                case .spectrum: SpectrumStageView(levels: spectrum.bands, isLive: spectrum.isLive,
                    isActive: nowPlaying.screensAwake, tint: .pink)
                case .music: NowPlayingView(nowPlaying: nowPlaying, spectrum: spectrum)
                }
            }
        }
        .padding(.horizontal, NotchLayout.expandedContentInset)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .foregroundStyle(NotchStyle.primaryText)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if viewModel.showsQuickActions {
                iconButton("返回工作台", symbol: "chevron.left") { viewModel.onOpenRequested?() }
                Text("快速搜索")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
            } else {
                ScrollView(.horizontal) {
                    segments
                }
                .scrollIndicators(.hidden)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            if !viewModel.showsQuickActions {
                Button {
                    viewModel.onOpenQuickActions?()
                } label: {
                    HStack(spacing: 5) {
                        Label("搜索", systemImage: "magnifyingglass")
                        Text("⌥⌘K")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(NotchStyle.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.white.opacity(0.07), in: Capsule())
                            .accessibilityHidden(true)
                    }
                    .fixedSize()
                }
                .buttonStyle(NotchButtonStyle())
                .help("快速搜索 · ⌥⌘K")
                if showsOverview {
                    iconButton(viewModel.isEditingWidgets ? "完成编辑" : "编辑组件",
                               symbol: viewModel.isEditingWidgets ? "checkmark" : "slider.horizontal.3",
                               tint: viewModel.isEditingWidgets ? .mint : .white) {
                        viewModel.isEditingWidgets.toggle()
                    }
                }
                iconButton(viewModel.isPinned ? "取消固定展开" : "固定展开",
                           symbol: viewModel.isPinned ? "pin.fill" : "pin",
                           tint: viewModel.isPinned ? .mint : .white) {
                    viewModel.isPinned.toggle()
                }
            }
            iconButton("收起", symbol: "xmark") { viewModel.onCloseRequested?() }
                .help("收起 · Escape")
        }
        .font(.system(size: 11, weight: .medium))
        .frame(height: 34)
    }

    private var segments: some View {
        HStack(spacing: 2) {
            segment("总览", symbol: "square.grid.2x2.fill", selected: showsOverview) {
                viewModel.onOpenRequested?()
            }
            tab(.music, title: "音乐", symbol: "music.note")
            tab(.timer, title: "番茄", symbol: "timer")
            tab(.capture, title: "速记", symbol: "square.and.pencil")
            tab(.files, title: "暂存", symbol: "tray.full")
            tab(.spectrum, title: "频谱", symbol: "waveform")
        }
        .padding(3)
        .background(.white.opacity(0.06), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工作台导航")
    }

    @ViewBuilder
    private func tab(_ tab: NotchViewModel.Tab, title: String, symbol: String) -> some View {
        if settings.isTabEnabled(tab) {
            segment(title, symbol: symbol,
                    selected: !showsOverview && viewModel.selectedWidget != .system && viewModel.selectedTab == tab) {
                viewModel.selectedWidget = nil
                viewModel.selectedTab = tab
                viewModel.isEditingWidgets = false
                viewModel.isInteractionLocked = false
                viewModel.showsDashboard = false
            }
        }
    }

    private func segment(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(selected || contrast == .increased ? NotchStyle.primaryText : NotchStyle.secondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(.white.opacity(selected ? 0.16 : 0), in: Capsule())
                .overlay {
                    if selected {
                        Capsule().strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.20), .clear], startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.75
                        ).allowsHitTesting(false)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(reduceMotion ? nil : NotchStyle.spring, value: selected)
    }

    private func iconButton(_ title: String, symbol: String, tint: Color = .white,
                            action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(NotchButtonStyle(tint: tint, shape: .circle(28)))
            .help(title)
    }
}
