import Foundation

enum DashboardWidget: String, CaseIterable, Codable, Identifiable {
    case music, timer, tasks, system
    var id: String { rawValue }
    var title: String {
        switch self { case .music: return "网易云音乐"; case .timer: return "番茄钟"
        case .tasks: return "今日任务"; case .system: return "系统监控" }
    }
    var symbol: String {
        switch self { case .music: return "music.note"; case .timer: return "timer"
        case .tasks: return "checklist"; case .system: return "cpu" }
    }
    var summary: String {
        switch self { case .music: return "播放控制与实时频谱"; case .timer: return "专注、休息与剩余时间"
        case .tasks: return "添加、完成与编辑每日任务"; case .system: return "CPU、内存和电池状态" }
    }
}

enum CompactWidget: String, CaseIterable, Codable, Identifiable {
    case system, timer, music, battery, none
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "CPU / 内存双环"; case .timer: return "番茄钟时间"
        case .music: return "音乐摘要"; case .battery: return "电池电量"; case .none: return "不显示" }
    }
}

enum MusicAppearance: String, CaseIterable, Codable, Identifiable {
    case vinyl, cover
    var id: String { rawValue }
    var title: String { self == .vinyl ? "黑胶唱片" : "专辑封面" }
}

/// Only presentation choices are stored here. Hiding a widget never touches its data.
struct WidgetLayout: Codable, Equatable {
    var widgets: [DashboardWidget] = DashboardWidget.allCases
    var leading: CompactWidget = .system
    var trailing: CompactWidget = .timer
    var showWave = true
    var musicAppearance: MusicAppearance = .vinyl
    var swipeTracks = true
    var systemStatusEnabled = true

    init() {}
    enum CodingKeys: String, CodingKey { case widgets, leading, trailing, showWave, musicAppearance, swipeTracks, systemStatusEnabled }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let stored = try c.decodeIfPresent([String].self, forKey: .widgets) {
            var seen = Set<DashboardWidget>()
            widgets = stored.compactMap(DashboardWidget.init(rawValue:)).filter { seen.insert($0).inserted }
        }
        leading = (try c.decodeIfPresent(String.self, forKey: .leading)).flatMap(CompactWidget.init(rawValue:)) ?? .system
        trailing = (try c.decodeIfPresent(String.self, forKey: .trailing)).flatMap(CompactWidget.init(rawValue:)) ?? .timer
        showWave = try c.decodeIfPresent(Bool.self, forKey: .showWave) ?? true
        musicAppearance = (try c.decodeIfPresent(String.self, forKey: .musicAppearance)).flatMap(MusicAppearance.init(rawValue:)) ?? .vinyl
        swipeTracks = try c.decodeIfPresent(Bool.self, forKey: .swipeTracks) ?? true
        systemStatusEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemStatusEnabled) ?? true
    }
    mutating func move(_ widget: DashboardWidget, to index: Int) {
        guard let old = widgets.firstIndex(of: widget) else { return }
        widgets.remove(at: old)
        widgets.insert(widget, at: min(max(0, index), widgets.count))
    }
    mutating func add(_ widget: DashboardWidget) {
        if !widgets.contains(widget) { widgets.append(widget) }
    }
    mutating func hide(_ widget: DashboardWidget) { widgets.removeAll { $0 == widget } }
}

/// Hit testing in rail coordinates supports differently sized cards and clamps edge drops.
enum WidgetReorder {
    static func targetIndex(from source: Int, translation: Double, widths: [Double], spacing: Double = 12) -> Int {
        guard widths.indices.contains(source) else { return 0 }
        var x = 0.0
        let centers = widths.map { width -> Double in
            defer { x += width + spacing }
            return x + width / 2
        }
        let destination = centers[source] + translation
        return centers.indices.min { abs(centers[$0] - destination) < abs(centers[$1] - destination) } ?? source
    }
}
