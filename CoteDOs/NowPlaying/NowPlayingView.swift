import AppKit
import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var nowPlaying: NowPlayingManager
    let spectrum: SpectrumAnalyzer
    @ObservedObject private var widgets = WidgetStore.shared
    @StateObject private var output = AudioOutputController()
    @State private var scrubFraction: Double?
    var portrait = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 24) {
                Button(action: nowPlaying.openCurrentTrack) {
                    MusicArtwork(url: nowPlaying.track?.artworkURL,
                        playing: nowPlaying.isPlaying && nowPlaying.screensAwake,
                        size: 118, appearance: widgets.layout.musicAppearance)
                }.buttonStyle(.plain).accessibilityLabel("打开当前音乐播放器")
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Circle().fill(nowPlaying.isPlaying ? NotchStyle.statusGreen : NotchStyle.tertiary).frame(width: 4, height: 4)
                        Text(nowPlaying.sourceName + (nowPlaying.isPlaying ? " · 正在播放" : " · 已暂停"))
                            .font(.system(size: 9)).foregroundStyle(NotchStyle.secondary)
                    }
                    Text(nowPlaying.track?.name ?? "等一首喜欢的歌")
                        .font(.system(size: 18, weight: .semibold)).lineLimit(2)
                        .help(nowPlaying.track?.name ?? "打开网易云、Apple Music 或 Spotify 开始播放")
                    Text(nowPlaying.track?.artist ?? "在播放器中开始播放，音乐会自动出现在这里")
                        .font(.system(size: 12.5)).foregroundStyle(NotchStyle.secondary).lineLimit(1)
                    if let album = nowPlaying.track?.album, !album.isEmpty {
                        Text(album).font(.system(size: 10)).foregroundStyle(NotchStyle.tertiary).lineLimit(1)
                    }
                    HStack(spacing: 12) {
                        ControlButton(systemName: "backward.fill", size: 13, label: "上一首", action: nowPlaying.previousTrack)
                        ControlButton(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 17,
                                      diameter: 40, filled: true, label: nowPlaying.isPlaying ? "暂停" : "播放",
                                      action: nowPlaying.playPause)
                        ControlButton(systemName: "forward.fill", size: 13, label: "下一首", action: nowPlaying.nextTrack)
                    }
                    .disabled(nowPlaying.track == nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 10) {
                    outputPicker
                    WidgetWave(spectrum: spectrum, active: nowPlaying.isPlaying && nowPlaying.screensAwake, compact: true)
                        .frame(height: 20)
                }
            }.frame(maxWidth: 520)
            VStack(spacing: 2) {
                Slider(value: Binding(get: { scrubFraction ?? nowPlaying.playbackFraction }, set: { scrubFraction = $0 }), in: 0...1) { editing in
                    if !editing, let value = scrubFraction, let duration = nowPlaying.track?.duration {
                        nowPlaying.seek(to: value * duration); scrubFraction = nil
                    }
                }.tint(NotchStyle.controlInk).controlSize(.small).disabled((nowPlaying.track?.duration ?? 0) <= 0)
                    .accessibilityLabel("歌曲播放进度")
                HStack {
                    Text(timeString((scrubFraction ?? nowPlaying.playbackFraction) * (nowPlaying.track?.duration ?? 0)))
                    Spacer()
                    if widgets.layout.swipeTracks { Text("两指左滑下一首 · 右滑上一首") }
                    Spacer()
                    Text(timeString(nowPlaying.track?.duration ?? 0))
                }.font(.system(size: 10)).monospacedDigit().foregroundStyle(NotchStyle.secondary)
            }.frame(maxWidth: 520)
            if let error = nowPlaying.commandError {
                HStack {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(error).font(.system(size: 10)).foregroundStyle(NotchStyle.secondary)
                    Button("打开播放器", action: nowPlaying.openCurrentTrack).buttonStyle(NotchButtonStyle()).font(.system(size: 10))
                }
            }
            if nowPlaying.permissionDenied {
                Button("允许读取播放器状态…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                }.buttonStyle(NotchButtonStyle()).font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            NotchArtworkWash(color: nowPlaying.artworkColor, center: UnitPoint(x: 0.24, y: 0.39))
                .clipShape(.rect(cornerRadius: NotchStyle.Radius.card))
        }
        .onAppear { output.start() }.onDisappear { output.stop() }
    }
    private var outputPicker: some View {
        Menu {
            ForEach(output.devices) { device in
                Button { output.select(device) } label: {
                    if device.id == output.currentDeviceID { Label(device.name, systemImage: "checkmark") }
                    else { Text(device.name) }
                }
            }
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 13)).frame(width: 32, height: 32)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("选择音频输出").help("选择扬声器或耳机")
    }
    private func timeString(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

extension NowPlayingManager {
    var playbackFraction: Double {
        guard let duration = track?.duration, duration.isFinite, duration > 0, position.isFinite else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var sourceName: String {
        activeSourceID == .auto ? "音乐" : activeSourceID.localizedName
    }
}
