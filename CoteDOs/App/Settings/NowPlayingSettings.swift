import SwiftUI

struct NowPlayingSettings: View {
    @ObservedObject var settings: UserSettings
    @ObservedObject private var widgets = WidgetStore.shared
    var body: some View {
        Form {
            Section("播放器") {
                Picker("音乐来源", selection: $settings.mediaSource) {
                    ForEach(UserSettings.MediaSource.allCases) { Text($0.localizedName).tag($0) }
                }
                Text("网易云使用独立的媒体控制通道，浏览器播放视频也不会将切歌或暂停转发给浏览器。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("音乐外观") {
                Picker("样式", selection: Binding(get: { widgets.layout.musicAppearance }, set: widgets.setMusicAppearance)) {
                    ForEach(MusicAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("播放时显示实时频谱", isOn: Binding(get: { widgets.layout.showWave }, set: widgets.setWave))
                Text("黑胶唱片在播放时缓缓旋转，暂停后停下。开启系统“减少动态效果”时，唱片保持静止。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("手势") {
                Toggle("左右滑动切歌", isOn: Binding(get: { widgets.layout.swipeTracks }, set: widgets.setSwipeTracks))
                Text("指针停在收起的刘海或音乐详情页：两指向左滑动播放下一首，向右播放上一首。卡片列表仍用于左右滚动。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(8)
    }
}
