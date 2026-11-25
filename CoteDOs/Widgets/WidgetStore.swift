import Combine
import Foundation

final class WidgetStore: ObservableObject {
    static let shared = WidgetStore()
    @Published private(set) var layout: WidgetLayout
    @Published private(set) var saveError: String?
    private let fileURL: URL

    init(fileURL: URL = Persistence.supportDirectory.appendingPathComponent("widget-layout.json")) {
        self.fileURL = fileURL
        layout = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(WidgetLayout.self, from: $0) } ?? WidgetLayout()
    }
    var available: [DashboardWidget] { DashboardWidget.allCases.filter { !layout.widgets.contains($0) } }
    func add(_ widget: DashboardWidget) { update { $0.add(widget) } }
    func hide(_ widget: DashboardWidget) { update { $0.hide(widget) } }
    func move(_ widget: DashboardWidget, to index: Int) { update { $0.move(widget, to: index) } }
    func move(_ widget: DashboardWidget, by offset: Int) {
        guard let index = layout.widgets.firstIndex(of: widget) else { return }
        move(widget, to: index + offset)
    }
    func setLeading(_ value: CompactWidget) { update { $0.leading = value } }
    func setTrailing(_ value: CompactWidget) { update { $0.trailing = value } }
    func setWave(_ value: Bool) { update { $0.showWave = value } }
    func setMusicAppearance(_ value: MusicAppearance) { update { $0.musicAppearance = value } }
    func setSwipeTracks(_ value: Bool) { update { $0.swipeTracks = value } }
    func setSystemStatusEnabled(_ value: Bool) { update { $0.systemStatusEnabled = value } }
    private func update(_ change: (inout WidgetLayout) -> Void) {
        var next = layout
        change(&next)
        guard next != layout else { return }
        layout = next
        save()
    }
    func save() {
        do {
            try JSONEncoder().encode(layout).write(to: fileURL, options: .atomic)
            saveError = nil
        } catch { saveError = "布局尚未保存，请重试。" }
    }
}
