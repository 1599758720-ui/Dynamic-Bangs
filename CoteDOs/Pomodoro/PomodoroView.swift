import SwiftUI

/// The timer tab in the expanded island: pick a named preset, watch the big
/// readout, and drive the session (start/pause/resume, reset, skip). The
/// passive readout in the collapsed pill mirrors the same session.
struct PomodoroView: View {
    @ObservedObject var pomodoro: PomodoroManager
    @ObservedObject private var settings = UserSettings.shared
    /// True on a side border: the chips run down the page instead of across
    /// it. Three German preset names come to ~330 pt in a row, which a ~200 pt
    /// column can only scroll — two chips visible and the third cut off at the
    /// edge. Stacked they all fit, and they use height the page has spare.
    var portrait: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if settings.timerPresets.isEmpty && pomodoro.phase == .idle {
                Text(String(localized: "timer.empty", defaultValue: "Keine Timer angelegt. Füge welche in den Einstellungen hinzu."))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            } else {
                VStack(spacing: 14) {
                    presetChips
                    readout
                    controlsRow
                }
                .frame(maxWidth: 340)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Preset chips

    @ViewBuilder private var presetChips: some View {
        if portrait {
            VStack(spacing: 6) {
                ForEach(settings.timerPresets) { preset in
                    chip(for: preset).frame(maxWidth: .infinity)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                presetTrack
                ScrollView(.horizontal) { presetTrack }
                    .scrollIndicators(.hidden)
            }
        }
    }

    private var presetTrack: some View {
        HStack(spacing: 4) {
            ForEach(settings.timerPresets) { preset in
                chip(for: preset)
            }
        }
        .padding(3)
        .fixedSize(horizontal: true, vertical: false)
        .background(.white.opacity(0.06), in: Capsule())
    }

    /// While a session is active the chips are locked: the session runs on a
    /// snapshot of its preset, so switching mid-run would only mislead.
    private func chip(for preset: TimerPreset) -> some View {
        let isSelected = selectedPreset?.id == preset.id
        let isLocked = pomodoro.phase != .idle
        return Button {
            pomodoro.selectedPresetID = preset.id
        } label: {
            Text(preset.name)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .lineLimit(1)
                .frame(height: 25)
                .padding(.horizontal, 10)
                // Stacked, the capsules line up on both edges — chips of
                // three different widths in a column read as a ragged list.
                .frame(maxWidth: portrait ? .infinity : nil)
                .background(.white.opacity(isSelected ? 0.16 : 0), in: Capsule())
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.7))
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .opacity(isLocked && !isSelected ? 0.4 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Readout

    private var selectedPreset: TimerPreset? {
        settings.timerPresets.first { $0.id == pomodoro.selectedPresetID } ?? settings.timerPresets.first
    }

    /// Live session readout, or the selected preset's duration as idle preview.
    private var displayText: String {
        if let text = pomodoro.pillText { return text }
        if let preset = selectedPreset { return preset.formattedDuration }
        return "--:--"
    }

    private var readout: some View {
        HStack(spacing: 26) {
            ZStack {
                UsageRing(value: pomodoro.phase == .idle ? 0 : pomodoro.progress,
                          color: .orange, lineWidth: 6, endColor: NotchStyle.amber, glowing: pomodoro.phase == .running)
                    .frame(width: 114, height: 114)
                Image(systemName: pomodoro.phase == .paused ? "pause.fill" : "timer")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(.orange)
            }.frame(width: 114, height: 114)
            VStack(alignment: .leading, spacing: 7) {
                Text(pomodoro.activeName ?? selectedPreset?.name ?? "准备专注")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(NotchStyle.secondary)
                Text(displayText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(pomodoro.phase == .paused ? NotchStyle.secondary : .white)
                if pomodoro.phase == .paused {
                    Text("已暂停").font(.system(size: 10)).foregroundStyle(NotchStyle.secondary)
                }
            }
        }
    }

    // MARK: Controls

    private var controlsRow: some View {
        HStack(spacing: 16) {
            ControlButton(systemName: "arrow.counterclockwise", size: 14,
                          label: "重置番茄钟", action: pomodoro.reset)
                .disabled(pomodoro.phase == .idle)
            ControlButton(systemName: pomodoro.phase == .running ? "pause.fill" : "play.fill", size: 17,
                          diameter: 42, color: .orange, filled: true,
                          label: pomodoro.phase == .running ? "暂停番茄钟" : "开始或继续番茄钟", action: primaryAction)
            if settings.timerAutoChain {
                ControlButton(systemName: "forward.end.fill", size: 14,
                              label: "跳到下一阶段", action: pomodoro.skip)
                    .disabled(pomodoro.phase == .idle)
            }
        }
    }

    private func primaryAction() {
        switch pomodoro.phase {
        case .idle:
            if let preset = selectedPreset { pomodoro.start(preset) }
        case .running:
            pomodoro.pause()
        case .paused:
            pomodoro.resume()
        }
    }
}
