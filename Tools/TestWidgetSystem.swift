import Foundation

@main
struct TestWidgetSystem {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CoteDOs-widget-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("layout.json")
        let store = WidgetStore(fileURL: url)
        precondition(store.layout.widgets == DashboardWidget.allCases)
        store.move(.system, to: 0)
        store.hide(.tasks)
        store.setLeading(.battery)
        store.setTrailing(.music)
        store.setWave(false)
        let restored = WidgetStore(fileURL: url)
        precondition(restored.layout == store.layout, "Order, hidden widgets and compact choices must survive relaunch")
        precondition(restored.available == [.tasks])
        restored.add(.tasks); restored.add(.tasks)
        precondition(restored.layout.widgets.filter { $0 == .tasks }.count == 1)
        restored.move(.tasks, to: -100)
        precondition(restored.layout.widgets.first == .tasks)
        restored.move(.tasks, to: 100)
        precondition(restored.layout.widgets.last == .tasks)
        for widget in DashboardWidget.allCases { restored.hide(widget) }
        precondition(WidgetStore(fileURL: url).layout.widgets.isEmpty, "An intentionally empty layout must not reset to defaults")
        let migrated = try JSONDecoder().decode(WidgetLayout.self,
            from: Data(#"{"widgets":["timer","future-widget","timer","system"]}"#.utf8))
        precondition(migrated.widgets == [.timer, .system] && migrated.leading == .system && migrated.showWave)
        precondition(store.saveError == nil)
        let bad = WidgetStore(fileURL: folder.appendingPathComponent("missing/layout.json"))
        bad.hide(.music)
        precondition(bad.saveError != nil && !bad.layout.widgets.contains(.music), "A failed save must retain the user's in-memory choices and expose recovery")
        precondition(WidgetReorder.targetIndex(from: 0, translation: 200, widths: [190, 146, 190, 190]) == 1)
        precondition(WidgetReorder.targetIndex(from: 3, translation: -1000, widths: [190, 146, 190, 190]) == 0)
        precondition(WidgetReorder.targetIndex(from: 0, translation: 1000, widths: [190, 146, 190, 190]) == 3)
        precondition(WidgetReorder.targetIndex(from: 1, translation: 5, widths: [190, 146, 190, 190]) == 1)
        let first = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let next = CPUTicks(user: 140, system: 60, idle: 900, nice: 0)
        precondition(next.utilization(since: first) == 0.5)
        precondition(first.utilization(since: first) == nil)
        let rollover = CPUTicks(user: 5, system: 0, idle: 5, nice: 0)
        let before = CPUTicks(user: .max - 4, system: 0, idle: .max - 4, nice: 0)
        precondition(rollover.utilization(since: before) == 0.5, "Counter wrap must not produce a huge usage spike")
        let live1 = SystemMetricReader.sample()
        Thread.sleep(forTimeInterval: 0.12)
        let live2 = SystemMetricReader.sample()
        guard let cpu1 = live1.cpu, let cpu2 = live2.cpu, let cpu = cpu2.utilization(since: cpu1),
              let memory = live2.memory else { fatalError("Could not read live Mach metrics") }
        precondition((0...1).contains(cpu) && memory.used > 0 && memory.used <= memory.total)
        if let battery = SystemMetricReader.battery() { precondition((0...1).contains(battery.fraction)) }
        print("PASS: widget persistence, hide/re-add, stable order, empty layout, migration, save failure recovery, CPU deltas/wrap, live CPU/memory/battery reads")
        print("Live CPU: \(Int(cpu * 100))%, memory estimate: \(memory.used / 1_048_576) / \(memory.total / 1_048_576) MiB")
    }
}
