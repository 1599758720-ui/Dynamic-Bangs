import SwiftUI

/// Compact presentation in either notch-flanking mode (left & right of the
/// physical camera housing at menu-bar height) or floating pill mode (external
/// display, off-home dock, or dropped-down transient activity).
///
/// Double-click and panel dragging are handled by AppKit. The button provides
/// the same open action to assistive technology.
struct CollapsedView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var pomodoro: PomodoroManager
    let spectrum: SpectrumAnalyzer
    let hasAudio: Bool
    var activity: NotchActivity?
    var flankLayout: NotchFlankLayout?
    @ObservedObject private var store = WidgetStore.shared
    @ObservedObject private var settings = UserSettings.shared
    @ObservedObject private var systemStatus = SystemStatus.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsFocus: Bool { store.layout.systemStatusEnabled && systemStatus.focusActive == true }
    private var showsTimerInSlot: Bool { store.layout.leading == .timer || store.layout.trailing == .timer }
    private var showsMusicInSlot: Bool { store.layout.leading == .music || store.layout.trailing == .music }

    var body: some View {
        Button { viewModel.onOpenRequested?() } label: {
            Group {
                if let flankLayout {
                    notchFlankingBody(flankLayout)
                } else {
                    floatingPillBody
                }
            }
            .offset(y: viewModel.isHovering && !reduceMotion ? -0.5 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .brightness(viewModel.isHovering ? 0.07 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: viewModel.isHovering)
        .accessibilityLabel("双击展开刘海工作台")
        .accessibilityValue(accessibilitySummary)
        .help(nowPlaying.track == nil ? "双击展开工作台 · 右键调整组件" : "双击展开 · 两指左滑下一首、右滑上一首")
        .contextMenu {
            if nowPlaying.track != nil {
                Button(nowPlaying.isPlaying ? "暂停音乐" : "播放音乐", action: nowPlaying.playPause)
                Button("上一首", action: nowPlaying.previousTrack)
                Button("下一首", action: nowPlaying.nextTrack)
                Divider()
            }
            Button("展开工作台") { viewModel.onOpenRequested?() }
            Button("快速搜索…") { viewModel.onOpenQuickActions?() }
            Button("固定展开工作台") { viewModel.onOpenRequested?(); viewModel.isPinned = true }
            Button("编辑组件") { viewModel.onOpenRequested?(); viewModel.isEditingWidgets = true }
            Button("缩略显示设置…") { WidgetPreferencesWindow.shared.show() }
        }
    }

    // MARK: - Notch-Flanking Layout (In Menu Bar Beside Hardware Camera)

    private func notchFlankingBody(_ flank: NotchFlankLayout) -> some View {
        HStack(spacing: 0) {
            if flank.leftWingWidth > 0 {
                flankLeadingContent(compact: flank.leftCompact)
                    .padding(.leading, flank.leadingTopFlare + 6)
                    .padding(.trailing, 6)
                    .frame(width: flank.leftWingWidth, height: flank.height, alignment: .center)
                    .clipped()
            }

            Color.clear
                .frame(width: flank.cameraGapWidth, height: flank.height)

            if flank.rightWingWidth > 0 {
                flankTrailingContent(compact: flank.rightCompact)
                    .padding(.leading, 6)
                    .padding(.trailing, flank.trailingTopFlare + 6)
                    .frame(width: flank.rightWingWidth, height: flank.height, alignment: .center)
                    .clipped()
            }
        }
        .frame(width: flank.frame.width, height: flank.height)
    }

    @ViewBuilder
    private func flankLeadingContent(compact: Bool) -> some View {
        HStack(spacing: 5) {
            if let swipe = viewModel.musicSwipe {
                Image(systemName: swipe.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
            } else if let activity {
                Image(systemName: activity.icon)
                    .font(.system(size: activity.kind == .audioRoute ? 15 : 14, weight: .semibold))
                    .foregroundStyle(activity.tint)
                    .transition(.opacity.combined(with: .scale(scale: 0.88)))
            } else {
                mini(store.layout.leading, compact: compact)
                if showsFocus && (!compact || store.layout.leading == .none) {
                    Image(systemName: "moon.fill")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.purple)
                        .help("系统专注模式已开启")
                }
            }
        }
    }

    @ViewBuilder
    private func flankTrailingContent(compact: Bool) -> some View {
        HStack(spacing: 5) {
            if let swipe = viewModel.musicSwipe {
                Text(swipe.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .transition(.opacity)
            } else if let activity {
                flankActivityTrailing(activity, compact: compact)
                    .transition(.opacity)
            } else {
                if hasAudio && store.layout.showWave && (!compact || store.layout.trailing == .none) {
                    WidgetWave(
                        spectrum: spectrum,
                        active: nowPlaying.screensAwake,
                        color: nowPlaying.artworkColor ?? .white,
                        compact: true
                    )
                    .frame(width: 16, height: 15)
                }
                if store.layout.trailing != .none {
                    mini(store.layout.trailing, compact: compact)
                } else if !showsTimerInSlot && pomodoro.pillText != nil {
                    timerSummary(compact: compact)
                }
            }
        }
    }

    @ViewBuilder
    private func flankActivityTrailing(_ activity: NotchActivity, compact: Bool) -> some View {
        if let progress = activity.progress {
            let fraction = CGFloat(min(max(progress, 0), 1))
            let barWidth: CGFloat = compact ? 48 : 68
            let label = activity.title.isEmpty ? "\(Int((fraction * 100).rounded()))%" : activity.title
            VStack(alignment: .trailing, spacing: 3) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(activity.tint)
                    .lineLimit(1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.20))
                    Capsule()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: barWidth * fraction)
                }
                .frame(width: barWidth, height: 4.5)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: fraction)
            }
        } else if let detail = activity.detail, !compact {
            VStack(alignment: .trailing, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(activity.tint)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        } else {
            Text(activity.title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(activity.tint)
                .lineLimit(1)
        }
    }

    // MARK: - Floating Pill Layout (External Display / Crowded Fallback)

    @ViewBuilder
    private var floatingPillBody: some View {
        Group {
            if let swipe = viewModel.musicSwipe, activity?.progress == nil {
                Label(swipe.title, systemImage: swipe.symbol)
                    .font(.subheadline.weight(.semibold))
            } else if let activity {
                ActivityCompactView(activity: activity)
            } else if viewModel.hasCompactContent(hasAudio: hasAudio, timerText: pomodoro.pillText) {
                floatingCompactRow
            } else {
                Image(nsImage: AppBrand.statusIcon())
            }
        }
    }

    private var floatingCompactRow: some View {
        HStack(spacing: 8) {
            mini(store.layout.leading, compact: false)
            if showsFocus {
                Image(systemName: "moon.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.purple)
                    .help("系统专注模式已开启")
            }
            if hasAudio && !showsMusicInSlot {
                if nowPlaying.isPlaying && nowPlaying.track != nil {
                    musicSummary(compact: false)
                } else {
                    Label("系统音频", systemImage: "speaker.wave.2")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if hasAudio && store.layout.showWave {
                WidgetWave(spectrum: spectrum, active: nowPlaying.screensAwake,
                           color: nowPlaying.artworkColor ?? .white, compact: true)
                    .frame(width: 18, height: 16)
            }
            if !showsTimerInSlot && pomodoro.pillText != nil { timerSummary(compact: false) }
            mini(store.layout.trailing, compact: false)
        }
        .padding(.horizontal, NotchLayout.compactContentInset)
    }

    // MARK: - Shared Mini Widgets

    private func timerSummary(compact: Bool) -> some View {
        HStack(spacing: 3) {
            if pomodoro.phase == .paused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            } else if pomodoro.phase == .running {
                Circle()
                    .fill(.orange)
                    .frame(width: compact ? 3.5 : 4.5, height: compact ? 3.5 : 4.5)
                    .shadow(color: .orange.opacity(reduceMotion ? 0 : 0.65), radius: 3)
                    .accessibilityHidden(true)
            }
            Text(pomodoro.remainingText ?? settings.timerPresets.first?.formattedDuration ?? "25:00")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .foregroundStyle(pomodoro.phase == .paused ? .white.opacity(0.72) : .white)
        }
    }

    private func musicSummary(compact: Bool) -> some View {
        HStack(spacing: 5) {
            MusicArtwork(
                url: nowPlaying.track?.artworkURL,
                playing: nowPlaying.isPlaying && nowPlaying.screensAwake,
                size: 22,
                appearance: store.layout.musicAppearance
            )
            if !compact {
                Text(nowPlaying.track?.name ?? "等待播放")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder
    private func mini(_ kind: CompactWidget, compact: Bool) -> some View {
        switch kind {
        case .system:
            CompactSystemRings()
                .scaleEffect(viewModel.isHovering && !reduceMotion ? 1.04 : 1)
        case .timer:
            timerSummary(compact: compact)
        case .music:
            musicSummary(compact: compact)
        case .battery:
            CompactBattery()
        case .none:
            EmptyView()
        }
    }

    private var accessibilitySummary: String {
        if let activity, let progress = activity.progress {
            let name = activity.title.isEmpty
                ? (activity.icon.hasPrefix("sun.") ? "亮度" : "音量")
                : activity.title
            return "\(name)，\(percentage(progress))"
        }
        if let swipe = viewModel.musicSwipe { return swipe.title }
        if let activity {
            return [activity.title, activity.detail].compactMap { $0 }.joined(separator: "，")
        }

        let showsSystem = store.layout.leading == .system || store.layout.trailing == .system
        let showsBattery = store.layout.leading == .battery || store.layout.trailing == .battery
        let track = hasAudio || showsMusicInSlot ? nowPlaying.track?.name : nil
        let timer = showsTimerInSlot || pomodoro.pillText != nil ? pomodoro.remainingText : nil
        return [track, timer, showsFocus ? "系统专注模式" : nil,
                showsSystem ? "CPU 与内存" : nil, showsBattery ? "电池" : nil]
            .compactMap { $0 }.joined(separator: "，")
    }
}
