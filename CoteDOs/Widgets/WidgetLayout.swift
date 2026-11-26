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

/// All positions are measured from the leading edge of the rail.
enum WidgetReorder {
    static let spacing = 12.0

    struct Preview {
        let targetIndex: Int
        /// The change in slot center for each card, indexed in the original order.
        let slotDisplacements: [Double]
        /// The dragged center relative to its projected drop slot.
        let settlingOffset: Double
    }

    static func centers(widths: [Double], spacing: Double = spacing) -> [Double] {
        var leading = 0.0
        return widths.map { width in
            defer { leading += width + spacing }
            return leading + width / 2
        }
    }

    static func preview(from source: Int, translation: Double, widths: [Double],
                        spacing: Double = spacing) -> Preview {
        let originalCenters = centers(widths: widths, spacing: spacing)
        guard widths.indices.contains(source) else {
            return Preview(targetIndex: 0, slotDisplacements: widths.map { _ in 0 }, settlingOffset: 0)
        }

        var widthsWithoutDragged = widths
        let draggedWidth = widthsWithoutDragged.remove(at: source)
        let draggedCenter = originalCenters[source] + translation
        var slotCenter = draggedWidth / 2
        var target = source
        var closestDistance = abs(translation)
        for index in widths.indices {
            let distance = abs(slotCenter - draggedCenter)
            if distance < closestDistance ||
                (distance == closestDistance && abs(index - source) < abs(target - source)) {
                target = index
                closestDistance = distance
            }
            if index < widthsWithoutDragged.count {
                slotCenter += widthsWithoutDragged[index] + spacing
            }
        }

        var order = Array(widths.indices)
        order.remove(at: source)
        order.insert(source, at: target)
        let projectedCenters = centers(widths: order.map { widths[$0] }, spacing: spacing)
        var displacements = widths.map { _ in 0.0 }
        for (index, originalIndex) in order.enumerated() {
            displacements[originalIndex] = projectedCenters[index] - originalCenters[originalIndex]
        }
        return Preview(targetIndex: target, slotDisplacements: displacements,
                       settlingOffset: draggedCenter - projectedCenters[target])
    }

    static func targetIndex(from source: Int, translation: Double, widths: [Double],
                            spacing: Double = spacing) -> Int {
        preview(from: source, translation: translation, widths: widths, spacing: spacing).targetIndex
    }

    static func rubberBand(_ translation: Double, limit: Double = 10) -> Double {
        limit * translation / (limit + abs(translation))
    }
}
