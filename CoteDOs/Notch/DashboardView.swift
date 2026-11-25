import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: NotchViewModel
    let nowPlaying: NowPlayingManager
    let pomodoro: PomodoroManager
    let spectrum: SpectrumAnalyzer
    var activity: NotchActivity?
    @ObservedObject private var store = WidgetStore.shared
    @State private var dragged: DashboardWidget?
    @State private var dragOffset: CGFloat = 0
    @State private var hoveredWidget: DashboardWidget?
    @State private var failedSystemTool: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                VStack(spacing: 12) {
                    if store.layout.widgets.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "rectangle.stack.badge.plus").font(.title2).foregroundStyle(NotchStyle.secondary)
                            Text("工作台里还没有组件").font(.system(size: 13, weight: .medium))
                            if !viewModel.isEditingWidgets { addMenu }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(store.layout.widgets) { widget in
                                    card(widget, proxy: proxy)
                                        .offset(x: dragged == widget ? dragOffset : 0)
                                        .scaleEffect(dragged == widget && !reduceMotion ? 1.025 : 1)
                                        .zIndex(dragged == widget ? 1 : 0)
                                }
                            }
                            .padding(.vertical, 4)
                            .coordinateSpace(name: "widgetRail")
                        }
                        .scrollIndicators(.hidden)
                        .frame(height: 212)
                    }
                    utilityStrip(proxy: proxy, width: geometry.size.width)
                    if let error = store.saveError {
                        HStack { Text(error); Button("重试") { store.save() } }
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("无法打开应用", isPresented: Binding(
            get: { failedSystemTool != nil },
            set: { if !$0 { failedSystemTool = nil } }
        )) {
            Button("好", role: .cancel) { failedSystemTool = nil }
        } message: {
            Text(failedSystemTool ?? "")
        }
    }

    private func utilityStrip(proxy: ScrollViewProxy, width: CGFloat) -> some View {
        let widgets = store.layout.widgets
        let railWidth = widgets.reduce(CGFloat.zero) { $0 + $1.cardWidth } + CGFloat(max(0, widgets.count - 1)) * 12
        return HStack(spacing: 8) {
            if viewModel.isEditingWidgets {
                addMenu
                Text("拖动卡片可排序")
                    .foregroundStyle(NotchStyle.secondary)
                    .lineLimit(1)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        Button("今日任务", systemImage: "checklist") { DailyTasksWindow.shared.show() }
                            .buttonStyle(NotchButtonStyle(tint: .mint, softTint: true))
                        ForEach(QuickActionsCatalog.availableSystemTools) { tool in
                            Button(tool.title, systemImage: tool.symbol) { launch(tool) }
                                .buttonStyle(NotchButtonStyle())
                        }
                        Button("组件设置", systemImage: "slider.horizontal.3") { WidgetPreferencesWindow.shared.show() }
                            .buttonStyle(NotchButtonStyle())
                        if let activity {
                            Label(activity.title, systemImage: activity.icon)
                                .foregroundStyle(activity.tint)
                                .padding(.horizontal, 9).frame(height: 26)
                                .background(activity.tint.opacity(0.12), in: Capsule())
                                .accessibilityValue(activity.progress.map { percentage($0) } ?? activity.detail ?? "")
                        }
                    }
                    .fixedSize()
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
            if railWidth > width, let first = widgets.first, let last = widgets.last {
                scrollButton("移到组件开头", symbol: "chevron.left", widget: first, anchor: .leading, proxy: proxy)
                scrollButton("移到组件末尾", symbol: "chevron.right", widget: last, anchor: .trailing, proxy: proxy)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .frame(height: 28)
    }

    private func scrollButton(_ title: String, symbol: String, widget: DashboardWidget,
                              anchor: UnitPoint, proxy: ScrollViewProxy) -> some View {
        Button(title, systemImage: symbol) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(widget.id, anchor: anchor) }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NotchButtonStyle(shape: .circle(26)))
        .help(title)
    }

    private func launch(_ tool: QuickActionItem) {
        guard let url = tool.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if error != nil {
                DispatchQueue.main.async { failedSystemTool = tool.title }
            }
        }
    }

    private var addMenu: some View {
        Menu {
            if store.available.isEmpty { Text("全部组件已添加") }
            ForEach(store.available) { widget in
                Button { store.add(widget) } label: { Label(widget.title, systemImage: widget.symbol) }
            }
        } label: {
            Label("添加组件", systemImage: "plus")
                .padding(.horizontal, 8).frame(height: 26)
        }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
        .background(.white.opacity(0.095), in: Capsule())
        .foregroundStyle(.white).disabled(store.available.isEmpty)
    }

    private func card(_ widget: DashboardWidget, proxy: ScrollViewProxy) -> some View {
        let hovered = hoveredWidget == widget
        let shape = RoundedRectangle(cornerRadius: NotchStyle.tileCornerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if viewModel.isEditingWidgets {
                    Image(systemName: "line.3.horizontal").foregroundColor(.white.opacity(0.65))
                        .frame(width: 18, height: 24).contentShape(Rectangle())
                        .help("拖动\(widget.title)调整顺序；也可使用旁边的菜单")
                        .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("widgetRail"))
                            .onChanged { value in
                                if dragged == nil { dragged = widget }
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                guard let start = store.layout.widgets.firstIndex(of: widget) else { dragged = nil; return }
                                let target = WidgetReorder.targetIndex(from: start, translation: Double(value.translation.width),
                                    widths: store.layout.widgets.map { Double($0.cardWidth) })
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                    store.move(widget, to: target)
                                    dragged = nil; dragOffset = 0
                                }
                                DispatchQueue.main.async {
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                                        proxy.scrollTo(widget.id, anchor: .center)
                                    }
                                }
                            })
                }
                HStack(spacing: 6) {
                    Image(systemName: widget.symbol).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(widget.tint).frame(width: 22, height: 22)
                        .background(widget.tint.opacity(0.12), in: Circle())
                    Text(widget.title).lineLimit(1).font(.system(size: 12.5, weight: .semibold))
                }
                Spacer(minLength: 2)
                if widget == .tasks { TasksProgress() }
                if viewModel.isEditingWidgets {
                    Menu {
                        Button("前移") { store.move(widget, by: -1) }.disabled(store.layout.widgets.first == widget)
                        Button("后移") { store.move(widget, by: 1) }.disabled(store.layout.widgets.last == widget)
                        Divider()
                        Button("隐藏组件，保留数据") { store.hide(widget) }
                    } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("调整\(widget.title)")
                } else {
                    Button { open(widget) } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(NotchButtonStyle(shape: .circle(24))).font(.system(size: 9))
                        .accessibilityLabel("打开\(widget.title)详情").help("打开\(widget.title)详情")
                }
            }.frame(height: 24)
            Group {
                switch widget {
                case .music: MusicWidgetBody(nowPlaying: nowPlaying, spectrum: spectrum)
                case .timer: TimerWidgetBody(pomodoro: pomodoro)
                case .tasks: TasksWidgetBody()
                case .system: SystemWidgetContent()
                }
            }
        }
        .padding(14).frame(width: widget.cardWidth, height: 204, alignment: .topLeading)
        .background {
            shape.fill(LinearGradient(
                colors: [hovered ? NotchStyle.tileHoverFillTop : NotchStyle.tileFillTop,
                         hovered ? NotchStyle.tileHoverFillBottom : NotchStyle.tileFillBottom],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay {
                shape.fill(RadialGradient(colors: [widget.tint.opacity(hovered ? 0.16 : 0.11), .clear],
                                          center: .topLeading, startRadius: 0, endRadius: 160))
            }
        }
        .overlay {
            Group {
                if viewModel.isEditingWidgets {
                    shape.strokeBorder(widget.tint.opacity(0.55), lineWidth: 0.65)
                } else {
                    shape.strokeBorder(LinearGradient(
                        colors: [.white.opacity(contrast == .increased ? 0.38 : 0.20), .white.opacity(0.05)],
                        startPoint: .top, endPoint: .bottom
                    ), lineWidth: 0.65)
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(shape)
        .onHover { hoveredWidget = $0 ? widget : nil }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hoveredWidget == widget)
        .id(widget.id)
    }

    private func open(_ widget: DashboardWidget) {
        if widget == .tasks { DailyTasksWindow.shared.show(); return }
        viewModel.selectedWidget = widget
        viewModel.selectedTab = widget == .timer ? .timer : .music
        viewModel.showsDashboard = false
    }
}

private extension DashboardWidget {
    var cardWidth: CGFloat {
        switch self {
        case .music: return 214
        case .timer: return 162
        case .tasks, .system: return 196
        }
    }
}

private struct MusicWidgetBody: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    let spectrum: SpectrumAnalyzer
    @ObservedObject private var store = WidgetStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Button(action: nowPlaying.openCurrentTrack) {
                MusicArtwork(url: nowPlaying.track?.artworkURL, playing: nowPlaying.isPlaying && nowPlaying.screensAwake,
                             size: 54, appearance: store.layout.musicAppearance)
                    .shadow(color: (nowPlaying.artworkColor ?? .black).opacity(0.30), radius: 9, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开当前音乐播放器")
            VStack(alignment: .leading, spacing: 3) {
                Text(nowPlaying.track?.name ?? "开始听歌")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .help(nowPlaying.track?.name ?? "在播放器中开始播放")
                Text(nowPlaying.track?.artist ?? "打开音乐播放器")
                    .font(.system(size: 11)).foregroundStyle(NotchStyle.secondary).lineLimit(1)
                if nowPlaying.track != nil {
                    Label(nowPlaying.sourceName, systemImage: "circle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(NotchStyle.secondary)
                        .lineLimit(1)
                }
            }
        }.frame(height: 56)

        GeometryReader { geometry in
            Capsule().fill(.white.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: geometry.size.width * nowPlaying.playbackFraction)
                }
        }
        .frame(height: 3)
        .accessibilityLabel("播放进度")
        .accessibilityValue(percentage(nowPlaying.playbackFraction))

        Spacer(minLength: 0)
        HStack(spacing: 7) {
            HStack(spacing: 8) {
                ControlButton(systemName: "backward.fill", size: 11, diameter: 28,
                              label: "上一首", action: nowPlaying.previousTrack)
                ControlButton(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 13,
                              diameter: 34, filled: true, label: nowPlaying.isPlaying ? "暂停" : "播放",
                              action: nowPlaying.playPause)
                ControlButton(systemName: "forward.fill", size: 11, diameter: 28,
                              label: "下一首", action: nowPlaying.nextTrack)
            }
            .disabled(nowPlaying.track == nil)
            Spacer(minLength: 0)
            if let error = nowPlaying.commandError {
                Button("重新连接", systemImage: "arrow.clockwise", action: nowPlaying.openCurrentTrack)
                    .labelStyle(.iconOnly)
                    .buttonStyle(NotchButtonStyle(tint: .orange, shape: .circle(26)))
                    .help(error)
            } else {
                WidgetWave(spectrum: spectrum, active: nowPlaying.isPlaying && nowPlaying.screensAwake,
                           color: nowPlaying.artworkColor ?? .pink, compact: true)
            }
        }
    }
}

struct WidgetWave: View {
    @ObservedObject var spectrum: SpectrumAnalyzer
    var active: Bool
    var color: Color = .white
    var compact = false
    var body: some View {
        LiveWaveBarsView(levels: spectrum.bands, isLive: spectrum.isLive, showsLiveBands: active, isActive: active,
            tint: color, count: compact ? 4 : 24, maxHeight: compact ? 13 : 23,
            barWidth: compact ? 2 : 3, spacing: compact ? 2 : 3)
            .accessibilityLabel(spectrum.isLive ? "实时系统音频频谱" : "频谱等待音频授权")
    }
}

private struct TimerWidgetBody: View {
    @ObservedObject var pomodoro: PomodoroManager
    @ObservedObject private var settings = UserSettings.shared

    private var preset: TimerPreset? {
        settings.timerPresets.first { $0.id == pomodoro.selectedPresetID } ?? settings.timerPresets.first
    }

    var body: some View {
        ZStack {
            UsageRing(value: pomodoro.phase == .idle ? 0 : pomodoro.progress,
                      color: .orange, lineWidth: 5.5, endColor: NotchStyle.amber, glowing: pomodoro.phase == .running)
                .frame(width: 88, height: 88)
            VStack(spacing: 3) {
                Text(pomodoro.remainingText ?? preset?.formattedDuration ?? "25:00")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(pomodoro.phase == .paused ? "已暂停" : (pomodoro.activeName ?? "准备专注"))
                    .font(.system(size: 9.5)).foregroundStyle(NotchStyle.secondary).lineLimit(1)
            }.frame(width: 68)
        }
        .frame(maxWidth: .infinity)
        Spacer(minLength: 0)
        HStack(spacing: 6) {
            Button {
                switch pomodoro.phase {
                case .running: pomodoro.pause()
                case .paused: pomodoro.resume()
                case .idle: if let preset { pomodoro.start(preset) }
                }
            } label: {
                Label(pomodoro.phase == .running ? "暂停" : (pomodoro.phase == .paused ? "继续" : "开始"),
                      systemImage: pomodoro.phase == .running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NotchButtonStyle(tint: .orange, softTint: true))
            .disabled(pomodoro.phase == .idle && preset == nil)
            Button("调整番茄钟时长", systemImage: "slider.horizontal.3") { TimerPresetWindow.shared.show() }
                .labelStyle(.iconOnly)
                .buttonStyle(NotchButtonStyle(shape: .circle(28)))
                .help("调整时长与休息安排")
        }
        .font(.system(size: 11, weight: .semibold))
    }
}

private struct TasksProgress: View {
    @ObservedObject private var tasks = DailyTasks.shared

    var body: some View {
        if !tasks.today.isEmpty {
            let done = tasks.today.filter(\.isDoneToday).count
            Text("\(done)/\(tasks.today.count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.mint)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.mint.opacity(0.12), in: Capsule())
                .accessibilityLabel("已完成 \(done) 项，共 \(tasks.today.count) 项")
        }
    }
}

private struct TasksWidgetBody: View {
    @ObservedObject private var tasks = DailyTasks.shared

    var body: some View {
        if tasks.today.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .light))
                Text("今天没有待办").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(NotchStyle.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(tasks.today.prefix(3)) { task in
                    HStack(spacing: 7) {
                        Button { tasks.toggle(task.id) } label: {
                            Image(systemName: task.isDoneToday ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(task.isDoneToday ? .mint : NotchStyle.secondary)
                                .frame(width: 19, height: 19)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel((task.isDoneToday ? "取消完成：" : "完成任务：") + task.title)
                        Button { DailyTasksWindow.shared.edit(task) } label: {
                            Text(task.title).font(.system(size: 12)).lineLimit(1)
                                .strikethrough(task.isDoneToday)
                                .foregroundStyle(task.isDoneToday ? NotchStyle.secondary : NotchStyle.primaryText)
                        }
                        .buttonStyle(.plain)
                        .help("编辑 \(task.title)")
                    }
                }
            }
            Spacer(minLength: 0)
        }

        HStack(spacing: 6) {
            Button {
                DailyTasksWindow.shared.edit()
            } label: {
                Label("新建", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(NotchButtonStyle(tint: .mint, softTint: true))
            Button("全部") { DailyTasksWindow.shared.show() }
                .buttonStyle(NotchButtonStyle())
        }
        .font(.system(size: 11, weight: .semibold))
    }
}

final class TimerPresetWindow {
    static let shared = TimerPresetWindow()
    private var window: NSWindow?
    func show() {
        if window == nil {
            window = NSWindow(contentViewController: NSHostingController(rootView: TimerSettings(settings: .shared)))
            window?.title = "番茄钟详细设置"
            window?.setContentSize(NSSize(width: 520, height: 540))
            window?.isReleasedWhenClosed = false
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
