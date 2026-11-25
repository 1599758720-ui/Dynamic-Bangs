import AppKit
import SwiftUI

struct WidgetPreferences: View {
    @ObservedObject private var store = WidgetStore.shared
    @ObservedObject private var status = SystemStatus.shared
    var body: some View {
        Form {
            Section("收起时显示") {
                Picker("刘海左侧", selection: Binding(get: { store.layout.leading }, set: store.setLeading)) {
                    ForEach(CompactWidget.allCases) { Text($0.title).tag($0) }
                }
                Picker("刘海右侧", selection: Binding(get: { store.layout.trailing }, set: store.setTrailing)) {
                    ForEach(CompactWidget.allCases) { Text($0.title).tag($0) }
                }
                Toggle("播放音乐时显示短频谱", isOn: Binding(get: { store.layout.showWave }, set: store.setWave))
                Text("外圈是 CPU，内圈是内存。番茄钟暂停时也会保留剩余时间。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("展开后的组件") {
                ForEach(store.layout.widgets) { widget in
                    HStack {
                        Label(widget.title, systemImage: widget.symbol)
                        Spacer()
                        Button { store.move(widget, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(store.layout.widgets.first == widget).accessibilityLabel("将\(widget.title)前移")
                        Button { store.move(widget, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(store.layout.widgets.last == widget).accessibilityLabel("将\(widget.title)后移")
                        Button("隐藏") { store.hide(widget) }.help("隐藏卡片，保留全部数据")
                    }
                }
                ForEach(store.available) { widget in
                    Button { store.add(widget) } label: { Label("添加\(widget.title)", systemImage: "plus.circle") }
                }
                Text("设置即时保存。也可以在刘海工作台的“编辑组件”中拖动卡片排序。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("音乐外观与手势") {
                Picker("音乐样式", selection: Binding(get: { store.layout.musicAppearance }, set: store.setMusicAppearance)) {
                    ForEach(MusicAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle("悬停刘海时左右滑动切歌", isOn: Binding(get: { store.layout.swipeTracks }, set: store.setSwipeTracks))
                Text("两指左滑下一首，右滑上一首。也支持音乐详情页；组件列表仍用于滚动卡片。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("系统动态提示") {
                Toggle("显示专注模式与解锁提示", isOn: Binding(get: { store.layout.systemStatusEnabled }, set: store.setSystemStatusEnabled))
                LabeledContent("专注状态", value: status.focusActive.map { $0 ? "已开启" : "已关闭" } ?? (status.focusAuthorization == .authorized ? "系统未共享状态" : "等待系统授权"))
                if status.focusAuthorization != .authorized {
                    Button(status.focusAuthorization == .denied ? "前往系统设置允许专注访问…" : "允许读取专注状态…") { status.requestFocusAccess() }
                        .disabled(status.focusAuthorization == .restricted)
                }
                Button("预览动态提示") { status.preview() }
                Text("锁屏时只显示锁图标，隐藏歌曲、任务和计时信息。专注状态仅用于本机提示。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = store.saveError {
                HStack { Text(error).foregroundStyle(.orange); Button("重试保存") { store.save() } }
            }
        }
        .formStyle(.grouped).padding(8).frame(width: 500, height: 650)
    }
}

final class WidgetPreferencesWindow {
    static let shared = WidgetPreferencesWindow()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: WidgetPreferences()))
            window.title = "刘海组件与缩略显示"
            window.isReleasedWhenClosed = false
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
