import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var viewModel: NotchViewModel
    let nowPlaying: NowPlayingManager
    let pomodoro: PomodoroManager
    let spectrum: SpectrumAnalyzer
    var activity: NotchActivity?
    @ObservedObject private var store = WidgetStore.shared
    @State private var drag: CardDrag?
    @State private var settling: Settlement?
    @State private var railOrigin: CGFloat = 0
    @GestureState private var trackingDrag = false
    @State private var failedSystemTool: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private struct CardDrag {
        let widget: DashboardWidget
        let widgets: [DashboardWidget]
        let railOrigin: CGFloat
        var translation: CGSize = .zero
    }

    private struct Settlement: Equatable {
        let widget: DashboardWidget
        let id = UUID()
    }

    private let cardHeight: CGFloat = 204
    private let spacing = CGFloat(WidgetReorder.spacing)
    private let railInset = NotchStyle.Spacing.railInset
    private var motion: Animation? { reduceMotion ? nil : NotchStyle.Motion.layout }

    private var railContentWidth: CGFloat {
        let widgets = store.layout.widgets
        return widgets.reduce(CGFloat.zero) { $0 + $1.cardWidth }
            + CGFloat(max(0, widgets.count - 1)) * spacing
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                VStack(spacing: NotchStyle.Spacing.xs) {
                    ZStack {
                        widgetRail(width: geometry.size.width)
                        if store.layout.widgets.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "rectangle.stack.badge.plus").font(.title2)
                                    .foregroundStyle(NotchStyle.secondary)
                                Text("工作台里还没有组件").font(.system(size: 13, weight: .medium))
                                if !viewModel.isEditingWidgets { addMenu }
                            }
                            .transition(.opacity)
                        }
                    }
                    .frame(height: cardHeight + 18)
                    utilityStrip(proxy: proxy, width: geometry.size.width)
                    if let error = store.saveError {
                        HStack { Text(error); Button("重试") { store.save() } }
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .coordinateSpace(name: "dashboardCanvas")
        .animation(motion, value: viewModel.isEditingWidgets)
        .onChange(of: viewModel.isEditingWidgets) { _, editing in
            if !editing { releaseDrag() }
        }
        .onChange(of: trackingDrag) { _, tracking in
            if !tracking { releaseDrag() }
        }
        .onChange(of: store.layout.widgets) { _, widgets in
            if let drag, drag.widgets != widgets { releaseDrag() }
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
        let railWidth = railContentWidth + 2 * railInset
        return HStack(spacing: NotchStyle.Spacing.md) {
            if viewModel.isEditingWidgets {
                addMenu
                Text("拖动卡片可排序")
                    .foregroundStyle(NotchStyle.secondary)
                    .lineLimit(1)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        Button("今日任务", systemImage: "checklist") { DailyTasksWindow.shared.show() }
                            .buttonStyle(NotchButtonStyle())
                        ForEach(QuickActionsCatalog.availableSystemTools) { tool in
                            Button(tool.title, systemImage: tool.symbol) { launch(tool) }
                                .buttonStyle(NotchButtonStyle())
                        }
                        Button("组件设置", systemImage: "slider.horizontal.3") { WidgetPreferencesWindow.shared.show() }
                            .buttonStyle(NotchButtonStyle())
                        if let activity {
                            Label(activity.title, systemImage: activity.icon)
                                .foregroundStyle(NotchStyle.primaryText)
                                .padding(.horizontal, 9).frame(height: 26)
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
        .font(NotchStyle.Typography.control)
        .padding(.horizontal, NotchStyle.Spacing.sm)
        .frame(height: 34)
        .overlay(alignment: .top) {
            Rectangle().fill(NotchStyle.hairline(contrast))
                .frame(height: NotchStyle.hairlineWidth)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func scrollButton(_ title: String, symbol: String, widget: DashboardWidget,
                              anchor: UnitPoint, proxy: ScrollViewProxy) -> some View {
        Button(title, systemImage: symbol) {
            withAnimation(motion) { proxy.scrollTo(widget.id, anchor: anchor) }
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
                Button { withAnimation(motion) { store.add(widget) } } label: { Label(widget.title, systemImage: widget.symbol) }
            }
        } label: {
            Label("添加组件", systemImage: "plus")
                .padding(.horizontal, 8).frame(height: 26)
        }
        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
        .foregroundStyle(NotchStyle.controlInk).disabled(store.available.isEmpty)
    }

    private func widgetRail(width: CGFloat) -> some View {
        let widgets = store.layout.widgets
        let widths = widgets.map { Double($0.cardWidth) }
        let centers = WidgetReorder.centers(widths: widths)
        let activeDrag = drag.flatMap { $0.widgets == widgets ? $0 : nil }
        let preview = activeDrag.flatMap { drag in
            widgets.firstIndex(of: drag.widget).map {
                WidgetReorder.preview(from: $0, translation: horizontalTranslation(of: drag), widths: widths)
            }
        }

        return ScrollView(.horizontal) {
            // Slot anchors keep scrolling independent from the visual positions of moving cards.
            HStack(spacing: spacing) {
                ForEach(widgets) { widget in
                    Color.clear.frame(width: widget.cardWidth, height: cardHeight).id(widget.id)
                }
            }
            .scrollTargetLayout()
            .accessibilityHidden(true)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(widgets.enumerated()), id: \.element) { index, widget in
                        let tracking = activeDrag?.widget == widget
                        let settlingHere = settling?.widget == widget
                        let slotShift = preview?.slotDisplacements[index] ?? 0
                        let dropDelta = tracking ? (preview?.settlingOffset ?? 0) : 0
                        let x = centers[index] - widths[index] / 2 + slotShift + dropDelta
                        let y = tracking && !reduceMotion
                            ? WidgetReorder.rubberBand(Double(activeDrag?.translation.height ?? 0)) : 0

                        card(widget, lifted: tracking)
                            .transaction { transaction in
                                if tracking { transaction.animation = nil }
                            } body: { content in
                                content.offset(x: x, y: y)
                            }
                            .zIndex(tracking ? 2 : settlingHere ? 1 : 0)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.frame(in: .named("dashboardCanvas")).minX
            } action: { railOrigin = $0 }
            .padding(.vertical, 9)
        }
        .contentMargins(.horizontal, railInset, for: .scrollContent)
        .scrollTargetBehavior(WidgetRailScrollBehavior(snaps: !trackingDrag && activeDrag == nil && settling == nil))
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .mask {
            if activeDrag != nil || settling != nil {
                // The panel silhouette is the only visible boundary for lifted cards.
                Rectangle()
                    .padding(.horizontal, -NotchLayout.expandedContentInset)
                    .padding(.vertical, -24)
            } else {
                railEdgeFade(width: width)
                    .padding(.vertical, -7)
            }
        }
    }

    private func railEdgeFade(width: CGFloat) -> some View {
        let fade = min(16 / max(width, 1), 0.5)
        let clipsLeft = railOrigin < railInset - 1
        let clipsRight = railOrigin + railContentWidth > width - railInset + 1
        return LinearGradient(stops: [
            .init(color: clipsLeft ? .clear : .black, location: 0),
            .init(color: .black, location: fade),
            .init(color: .black, location: 1 - fade),
            .init(color: clipsRight ? .clear : .black, location: 1),
        ], startPoint: UnitPoint(x: 0, y: 0.5), endPoint: UnitPoint(x: 1, y: 0.5))
    }

    private func horizontalTranslation(of drag: CardDrag) -> Double {
        Double(drag.translation.width + drag.railOrigin - railOrigin)
    }

    private func cardDragGesture(for widget: DashboardWidget) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("dashboardCanvas"))
            .updating($trackingDrag) { _, tracking, _ in tracking = true }
            .onChanged { value in
                guard viewModel.isEditingWidgets, settling == nil else { return }
                let widgets = store.layout.widgets
                if drag == nil {
                    drag = CardDrag(widget: widget, widgets: widgets, railOrigin: railOrigin)
                }
                guard drag?.widget == widget, drag?.widgets == widgets,
                      let current = drag, let source = widgets.firstIndex(of: widget) else { return }
                let widths = widgets.map { Double($0.cardWidth) }
                var next = current
                next.translation = value.translation
                let previousTarget = WidgetReorder.targetIndex(from: source,
                    translation: horizontalTranslation(of: current), widths: widths)
                let nextTarget = WidgetReorder.targetIndex(from: source,
                    translation: horizontalTranslation(of: next), widths: widths)
                withAnimation(previousTarget == nextTarget ? nil : motion) { drag = next }
            }
            .onEnded { value in
                guard var drag, drag.widget == widget, drag.widgets == store.layout.widgets,
                      let source = drag.widgets.firstIndex(of: widget) else { return }
                drag.translation = value.translation
                let target = WidgetReorder.targetIndex(from: source,
                    translation: horizontalTranslation(of: drag), widths: drag.widgets.map { Double($0.cardWidth) })
                releaseDrag(to: target)
            }
    }

    private func releaseDrag(to target: Int? = nil) {
        guard let drag else { return }
        let release = Settlement(widget: drag.widget)
        settling = release
        // With stable card identities and absolute offsets, the spring starts at the
        // presentation position even though the underlying order changes immediately.
        withAnimation(motion, completionCriteria: .removed) {
            self.drag = nil
            if let target { store.move(drag.widget, to: target) }
        } completion: {
            if settling == release { settling = nil }
        }
    }

    private func card(_ widget: DashboardWidget, lifted: Bool) -> some View {
        let editing = viewModel.isEditingWidgets
        return VStack(alignment: .leading, spacing: NotchStyle.Spacing.lg) {
            HStack(spacing: NotchStyle.Spacing.sm) {
                Image(systemName: widget.symbol)
                    .font(NotchStyle.Typography.cardSymbol)
                    .foregroundStyle(NotchStyle.headerSymbol(contrast))
                    .accessibilityHidden(true)
                Text(widget.title).font(NotchStyle.Typography.cardTitle)
                    .foregroundStyle(NotchStyle.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if !editing {
                    if widget == .tasks { TasksProgress() }
                    Button { open(widget) } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(NotchButtonStyle(shape: .circle(24))).font(.system(size: 9))
                        .accessibilityLabel("打开\(widget.title)")
                        .help("打开详情")
                        .transition(.opacity)
                }
            }
            .frame(height: 24)

            Group {
                switch widget {
                case .music: MusicWidgetBody(nowPlaying: nowPlaying, spectrum: spectrum)
                case .timer: TimerWidgetBody(pomodoro: pomodoro)
                case .tasks: TasksWidgetBody()
                case .system: SystemWidgetContent()
                }
            }
        }
        .padding(NotchStyle.Spacing.cardPadding)
        .frame(width: widget.cardWidth, height: cardHeight, alignment: .topLeading)
        .background {
            if widget == .music {
                MusicWidgetWash(nowPlaying: nowPlaying)
                    .clipShape(.rect(cornerRadius: NotchStyle.Radius.card))
            }
        }
        .allowsHitTesting(!editing)
        .accessibilityHidden(editing)
        .modifier(NotchTileChrome(lifted: lifted))
        .overlay {
            if editing {
                reorderSurface(widget)
            }
        }
        .overlay(alignment: .topTrailing) {
            if editing {
                Button("隐藏\(widget.title)", systemImage: "minus") {
                    withAnimation(motion) { store.hide(widget) }
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(NotchButtonStyle(tint: NotchStyle.headerSymbol(contrast), shape: .circle(24)))
                .help("隐藏组件并保留数据")
                .padding(NotchStyle.Spacing.cardPadding)
                .transition(.opacity)
            }
        }
        .scaleEffect(lifted && !reduceMotion ? 1.035 : 1)
        .animation(motion, value: lifted)
        .accessibilityElement(children: .contain)
    }

    private func reorderSurface(_ widget: DashboardWidget) -> some View {
        let widgets = store.layout.widgets
        return Color.clear
            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.Radius.card))
            .highPriorityGesture(cardDragGesture(for: widget))
            .focusable()
            .onKeyPress(.leftArrow) { move(widget, by: -1) }
            .onKeyPress(.rightArrow) { move(widget, by: 1) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(widget.title)
            .accessibilityHint("左右拖动或按方向键调整顺序")
            .accessibilityActions {
                if widgets.first != widget {
                    Button("前移") { _ = move(widget, by: -1) }
                }
                if widgets.last != widget {
                    Button("后移") { _ = move(widget, by: 1) }
                }
            }
    }

    private func move(_ widget: DashboardWidget, by step: Int) -> KeyPress.Result {
        let widgets = store.layout.widgets
        guard drag == nil, settling == nil,
              let index = widgets.firstIndex(of: widget), widgets.indices.contains(index + step) else {
            return .ignored
        }
        withAnimation(motion) { store.move(widget, by: step) }
        return .handled
    }

    private func open(_ widget: DashboardWidget) {
        if widget == .tasks { DailyTasksWindow.shared.show(); return }
        viewModel.selectedWidget = widget
        viewModel.selectedTab = widget == .timer ? .timer : .music
        viewModel.showsDashboard = false
    }
}

/// Keep the same ScrollView and registered card targets throughout reordering.
private struct WidgetRailScrollBehavior: ScrollTargetBehavior {
    let snaps: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        if snaps {
            ViewAlignedScrollTargetBehavior(limitBehavior: .automatic).updateTarget(&target, context: context)
        }
    }
}

private struct MusicWidgetWash: View {
    @ObservedObject var nowPlaying: NowPlayingManager

    var body: some View {
        NotchArtworkWash(color: nowPlaying.artworkColor, center: UnitPoint(x: 0.23, y: 0.29))
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
                        .font(.system(size: 9))
                        .foregroundStyle(NotchStyle.secondary)
                        .lineLimit(1)
                }
            }
        }.frame(height: 56)

        GeometryReader { geometry in
            Capsule().fill(NotchStyle.controlInk.opacity(0.13))
                .overlay(alignment: .leading) {
                    Capsule().fill(NotchStyle.controlInk).frame(width: geometry.size.width * nowPlaying.playbackFraction)
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
                WidgetWave(spectrum: spectrum, active: nowPlaying.isPlaying && nowPlaying.screensAwake, compact: true)
            }
        }
    }
}

struct WidgetWave: View {
    @ObservedObject var spectrum: SpectrumAnalyzer
    var active: Bool
    var color: Color?
    var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = color ?? (scheme == .dark ? .white : .black)
        LiveWaveBarsView(levels: spectrum.bands, isLive: spectrum.isLive, showsLiveBands: active, isActive: active,
            tint: ink, count: compact ? 4 : 24, maxHeight: compact ? 13 : 23,
            barWidth: compact ? 2 : 3, spacing: compact ? 2 : 3)
            .accessibilityLabel(spectrum.isLive ? "实时系统音频频谱" : "频谱等待音频授权")
    }
}

private struct TimerWidgetBody: View {
    @ObservedObject var pomodoro: PomodoroManager
    @ObservedObject private var settings = UserSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var preset: TimerPreset? {
        settings.timerPresets.first { $0.id == pomodoro.selectedPresetID } ?? settings.timerPresets.first
    }

    var body: some View {
        ZStack {
            UsageRing(value: pomodoro.phase == .idle ? 0 : pomodoro.progress,
                      color: NotchStyle.focusOrange, lineWidth: 5.5, glowing: pomodoro.phase == .running)
                .frame(width: 88, height: 88)
            VStack(spacing: 3) {
                Text(pomodoro.remainingText ?? preset?.formattedDuration ?? "25:00")
                    .font(NotchStyle.Typography.metric(20))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                Text(pomodoro.phase == .paused ? "已暂停" : (pomodoro.activeName ?? "准备专注"))
                    .font(.system(size: 9.5)).foregroundStyle(NotchStyle.secondary).lineLimit(1)
            }.frame(width: 68)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : NotchStyle.Motion.surface, value: pomodoro.phase)
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
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }
            .buttonStyle(NotchButtonStyle(tint: pomodoro.phase == .running ? NotchStyle.focusOrange : NotchStyle.controlInk))
            .disabled(pomodoro.phase == .idle && preset == nil)
            Button("调整番茄钟时长", systemImage: "slider.horizontal.3") { TimerPresetWindow.shared.show() }
                .labelStyle(.iconOnly)
                .buttonStyle(NotchButtonStyle(shape: .circle(28)))
                .help("调整时长与休息安排")
        }
        .font(NotchStyle.Typography.control)
        .animation(reduceMotion ? nil : NotchStyle.Motion.surface, value: pomodoro.phase)
    }
}

private struct TasksProgress: View {
    @ObservedObject private var tasks = DailyTasks.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !tasks.today.isEmpty {
            let done = tasks.today.filter(\.isDoneToday).count
            Text("\(done)/\(tasks.today.count)")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(done == tasks.today.count ? NotchStyle.taskAccent : NotchStyle.secondary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : NotchStyle.Motion.surface, value: done)
                .accessibilityLabel("已完成 \(done) 项，共 \(tasks.today.count) 项")
        }
    }
}

private struct TasksWidgetBody: View {
    @ObservedObject private var tasks = DailyTasks.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if tasks.today.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle").font(.system(size: 22, weight: .light))
                Text("今天没有待办").font(NotchStyle.Typography.control)
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
                                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        }
                        .buttonStyle(NotchButtonStyle(tint: task.isDoneToday ? NotchStyle.taskAccent : NotchStyle.secondary,
                                                    shape: .circle(20)))
                        .accessibilityLabel((task.isDoneToday ? "取消完成：" : "完成任务：") + task.title)
                        Button { DailyTasksWindow.shared.edit(task) } label: {
                            Text(task.title).font(.system(size: 12)).lineLimit(1)
                                .strikethrough(task.isDoneToday)
                                .foregroundStyle(task.isDoneToday ? NotchStyle.secondary : NotchStyle.primaryText)
                        }
                        .buttonStyle(.plain)
                        .help("编辑 \(task.title)")
                    }
                    .animation(reduceMotion ? nil : NotchStyle.Motion.surface, value: task.isDoneToday)
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
            .buttonStyle(NotchButtonStyle())
            Button("全部") { DailyTasksWindow.shared.show() }
                .buttonStyle(NotchButtonStyle())
        }
        .font(NotchStyle.Typography.control)
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
