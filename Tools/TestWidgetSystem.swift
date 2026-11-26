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
        testLiveReorder()
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
        print("PASS: widget persistence, hide/re-add, stable order, live drag and drop continuity, empty layout, migration, save failure recovery, CPU deltas/wrap, live CPU/memory/battery reads")
        print("Live CPU: \(Int(cpu * 100))%, memory estimate: \(memory.used / 1_048_576) / \(memory.total / 1_048_576) MiB")
    }

    static func testLiveReorder() {
        let widths = [214.0, 162, 196, 196]
        let centers = WidgetReorder.centers(widths: widths)
        precondition(centers == [107, 307, 498, 706])

        func preview(_ source: Int, _ translation: Double) -> WidgetReorder.Preview {
            WidgetReorder.preview(from: source, translation: translation, widths: widths)
        }

        // The first swap is halfway between the two attainable dragged-card centers.
        precondition(preview(0, 87).targetIndex == 0)
        let right = preview(0, 87.25)
        precondition(right.targetIndex == 1 && right.slotDisplacements == [174, -226, 0, 0])
        precondition(right.settlingOffset == -86.75)
        precondition(preview(0, 86.75).slotDisplacements == [0, 0, 0, 0], "Reversing across a threshold restores the old slot")

        precondition(preview(1, -113).targetIndex == 1)
        let left = preview(1, -113.25)
        precondition(left.targetIndex == 0 && left.slotDisplacements == [174, -226, 0, 0])
        precondition(left.settlingOffset == 112.75)
        let farRight = preview(0, 10_000)
        precondition(farRight.targetIndex == 3 && farRight.slotDisplacements == [590, -226, -226, -226])
        let farLeft = preview(3, -10_000)
        precondition(farLeft.targetIndex == 0 && farLeft.slotDisplacements == [208, 208, 208, -608])

        let single = WidgetReorder.preview(from: 0, translation: 231, widths: [162])
        precondition(single.targetIndex == 0 && single.slotDisplacements == [0] && single.settlingOffset == 231)
        let invalid = WidgetReorder.preview(from: 1, translation: -50, widths: [])
        precondition(invalid.targetIndex == 0 && invalid.slotDisplacements.isEmpty && invalid.settlingOffset == 0)
        precondition(WidgetReorder.preview(from: -1, translation: 20, widths: widths).slotDisplacements == [0, 0, 0, 0])
        let customSpacing = WidgetReorder.preview(from: 0, translation: 140, widths: [100, 120], spacing: 20)
        precondition(customSpacing.targetIndex == 1 && customSpacing.slotDisplacements == [140, -120])
        precondition(customSpacing.settlingOffset == 0)

        for source in widths.indices {
            for translation in stride(from: -850.5, through: 850.5, by: 0.5) {
                let live = preview(source, translation)
                var order = Array(widths.indices)
                order.remove(at: source)
                order.insert(source, at: live.targetIndex)
                let finalCenters = WidgetReorder.centers(widths: order.map { widths[$0] })

                for (destination, original) in order.enumerated() {
                    let previewCenter = centers[original] + live.slotDisplacements[original]
                    precondition(previewCenter == finalCenters[destination], "Each neighbor lands at its exact post-drop center")
                }
                precondition(finalCenters[live.targetIndex] + live.settlingOffset == centers[source] + translation,
                             "The drop offset must reconstruct the dragged card's exact rendered center")
            }
        }

        precondition(WidgetReorder.rubberBand(0) == 0)
        precondition(WidgetReorder.rubberBand(10) == 5 && WidgetReorder.rubberBand(-10) == -5)
        precondition(abs(WidgetReorder.rubberBand(10_000)) < 10)
        precondition(abs(WidgetReorder.rubberBand(-10_000)) < 10)
    }
}
