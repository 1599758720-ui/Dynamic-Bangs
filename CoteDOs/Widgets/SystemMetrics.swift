import AppKit
import Combine
import Darwin
import IOKit.ps

struct CPUTicks: Equatable {
    let user: UInt32, system: UInt32, idle: UInt32, nice: UInt32
    /// Mach counters are cumulative and can wrap. Never treat a first reading as utilization.
    func utilization(since previous: CPUTicks) -> Double? {
        func delta(_ a: UInt32, _ b: UInt32) -> UInt64 { UInt64(a &- b) }
        let busy = delta(user, previous.user) + delta(system, previous.system) + delta(nice, previous.nice)
        let total = busy + delta(idle, previous.idle)
        return total > 0 ? min(1, Double(busy) / Double(total)) : nil
    }
}

struct MemoryReading: Equatable {
    let used: UInt64, total: UInt64
    var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
}
struct BatteryReading: Equatable {
    let fraction: Double
    let charging: Bool
    let onAC: Bool
}

enum SystemMetricReader {
    static func sample() -> (cpu: CPUTicks?, memory: MemoryReading?) {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = host_cpu_load_info_data_t()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        let ticks: CPUTicks? = cpuResult == KERN_SUCCESS
            ? CPUTicks(user: cpu.cpu_ticks.0, system: cpu.cpu_ticks.1, idle: cpu.cpu_ticks.2, nice: cpu.cpu_ticks.3) : nil
        var vm = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let vmResult = withUnsafeMutablePointer(to: &vm) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        var memory: MemoryReading?
        if vmResult == KERN_SUCCESS, pageResult == KERN_SUCCESS {
            // A documented local estimate: active + wired + compressed physical pages.
            let pages = UInt64(vm.active_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
            let total = ProcessInfo.processInfo.physicalMemory
            memory = MemoryReading(used: min(total, pages * UInt64(pageSize)), total: total)
        }
        return (ticks, memory)
    }

    static func battery() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let capacity = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            return BatteryReading(fraction: min(1, max(0, Double(capacity) / Double(maximum))),
                charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }
}

/// Two-second sampling only while a visible widget needs it. Battery uses IOKit notifications.
final class SystemMetrics: ObservableObject {
    static let shared = SystemMetrics()
    @Published private(set) var cpu: Double?
    @Published private(set) var memory: MemoryReading?
    @Published private(set) var battery: BatteryReading?
    private var previousCPU: CPUTicks?
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?

    func setDemand(system: Bool, battery needsBattery: Bool) {
        if system, timer == nil {
            previousCPU = nil
            sample()
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !system {
            timer?.invalidate(); timer = nil; previousCPU = nil
        }
        if needsBattery, powerSource == nil {
            refreshBattery()
            let context = Unmanaged.passUnretained(self).toOpaque()
            let callback: IOPowerSourceCallbackType = { pointer in
                guard let pointer else { return }
                Unmanaged<SystemMetrics>.fromOpaque(pointer).takeUnretainedValue().refreshBattery()
            }
            if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
                powerSource = source
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
        } else if !needsBattery, let source = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = nil
        }
    }
    private func sample() {
        let reading = SystemMetricReader.sample()
        let nextCPU = reading.cpu.flatMap { current in previousCPU.flatMap { current.utilization(since: $0) } }
        previousCPU = reading.cpu
        if cpu != nextCPU { cpu = nextCPU }
        if memory != reading.memory { memory = reading.memory }
    }
    private func refreshBattery() {
        let next = SystemMetricReader.battery()
        if battery != next { battery = next }
    }
    deinit {
        timer?.invalidate()
        if let source = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
